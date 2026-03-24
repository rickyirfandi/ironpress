use std::borrow::Cow;
use std::io::Cursor;

use image::{DynamicImage, GenericImageView, ImageFormat, ImageReader};
use mozjpeg_rs::{Preset, Subsampling, TrellisConfig};

use crate::error::CompressError;
use crate::options::{ChromaSubsampling, CompressParams, OutputFormat};

/// Maximum binary search iterations to prevent runaway loops.
const MAX_BINARY_SEARCH_ITERATIONS: u32 = 10;
/// Maximum resize-and-retry cycles.
const MAX_RESIZE_CYCLES: u32 = 4;
/// Scale factor applied when auto-resizing to meet file size target.
const RESIZE_SCALE_FACTOR: f64 = 0.75;

/// Detected input format (also used as output format selector).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DetectedFormat {
    Jpeg,
    Png,
    WebpLossless,
    WebpLossy,
}

/// Pre-converted pixel buffer to avoid redundant `to_rgb8()`/`to_rgba8()`
/// calls during binary search iterations. For a 12MP image each conversion
/// allocates ~36 MB, so converting once instead of 10× eliminates ~360 MB
/// of allocation churn per compression call.
enum PreparedPixels {
    Rgb {
        data: Vec<u8>,
        width: u32,
        height: u32,
    },
    Rgba {
        data: Vec<u8>,
        width: u32,
        height: u32,
    },
}

impl PreparedPixels {
    fn dimensions(&self) -> (u32, u32) {
        match self {
            Self::Rgb { width, height, .. } | Self::Rgba { width, height, .. } => (*width, *height),
        }
    }
}

fn prepare_pixels(img: &DynamicImage, format: DetectedFormat) -> PreparedPixels {
    match format {
        DetectedFormat::Jpeg => {
            let rgb = img.to_rgb8();
            let (w, h) = rgb.dimensions();
            PreparedPixels::Rgb {
                data: rgb.into_raw(),
                width: w,
                height: h,
            }
        }
        _ => {
            let rgba = img.to_rgba8();
            let (w, h) = rgba.dimensions();
            PreparedPixels::Rgba {
                data: rgba.into_raw(),
                width: w,
                height: h,
            }
        }
    }
}

/// Internal result from the compression engine.
pub struct EngineResult {
    pub data: Vec<u8>,
    pub width: u32,
    pub height: u32,
    pub quality_used: u32,
    pub iterations: u32,
    pub resized_to_fit: bool,
}

// ─── Public API ──────────────────────────────────────────────────────────────

/// Compress raw image bytes with the given parameters.
pub fn compress_bytes(
    input: &[u8],
    params: &CompressParams,
) -> Result<EngineResult, CompressError> {
    let original_format = detect_format(input)?;
    let img =
        image::load_from_memory(input).map_err(|e| CompressError::DecodeError(e.to_string()))?;
    let output_format = resolve_output_format(params, original_format);
    let jpeg_exif = resolve_jpeg_exif_payload(input, original_format, output_format, params)?;

    // Apply explicit resize constraints first
    let img = apply_resize_constraints(&img, params.max_width, params.max_height);

    if params.max_file_size > 0 {
        compress_to_target_size(&img, params, output_format, jpeg_exif.as_deref())
    } else {
        let quality = params.quality.min(100) as u8;
        let encoded = encode_image(&img, quality, output_format, params, jpeg_exif.as_deref())?;
        let (w, h) = img.dimensions();
        Ok(EngineResult {
            data: encoded,
            width: w,
            height: h,
            quality_used: quality as u32,
            iterations: 1,
            resized_to_fit: false,
        })
    }
}

// ─── Target Size Binary Search ───────────────────────────────────────────────

fn compress_to_target_size(
    original_img: &DynamicImage,
    params: &CompressParams,
    output_format: DetectedFormat,
    jpeg_exif: Option<&[u8]>,
) -> Result<EngineResult, CompressError> {
    let target = params.max_file_size as usize;
    let min_q = params.min_quality.min(100) as u8;
    let allow_resize = params.allow_resize != 0;

    let mut img = Cow::Borrowed(original_img);
    let mut total_iterations: u32 = 0;
    let mut resized = false;

    // Pre-convert pixel data once — avoids redundant to_rgb8()/to_rgba8()
    // on every binary search iteration (up to 10× per resize cycle).
    let mut prepared = prepare_pixels(&img, output_format);

    for _resize_cycle in 0..MAX_RESIZE_CYCLES {
        // First, try at the requested quality — often it's already small enough
        let initial_q = params.quality.min(100) as u8;
        let initial_encoded =
            encode_image_prepared(&prepared, &img, initial_q, output_format, params, jpeg_exif)?;
        total_iterations += 1;

        if initial_encoded.len() <= target {
            let (w, h) = prepared.dimensions();
            return Ok(EngineResult {
                data: initial_encoded,
                width: w,
                height: h,
                quality_used: initial_q as u32,
                iterations: total_iterations,
                resized_to_fit: resized,
            });
        }

        // Binary search: find highest quality that fits under target
        let search_result = binary_search_quality(
            &prepared,
            &img,
            min_q,
            initial_q.saturating_sub(1),
            target,
            output_format,
            params,
            jpeg_exif,
        )?;
        total_iterations += search_result.iterations;

        if let Some((best_data, best_q)) = search_result.best {
            let (w, h) = prepared.dimensions();
            return Ok(EngineResult {
                data: best_data,
                width: w,
                height: h,
                quality_used: best_q as u32,
                iterations: total_iterations,
                resized_to_fit: resized,
            });
        }

        // Even min_quality didn't fit — try resize if allowed
        if !allow_resize {
            // Encode at min quality as best effort
            let fallback =
                encode_image_prepared(&prepared, &img, min_q, output_format, params, jpeg_exif)?;
            total_iterations += 1;
            let (w, h) = prepared.dimensions();
            return Ok(EngineResult {
                data: fallback,
                width: w,
                height: h,
                quality_used: min_q as u32,
                iterations: total_iterations,
                resized_to_fit: false,
            });
        }

        // Downscale and retry
        let (cur_w, cur_h) = img.dimensions();
        let new_w = ((cur_w as f64) * RESIZE_SCALE_FACTOR).max(16.0) as u32;
        let new_h = ((cur_h as f64) * RESIZE_SCALE_FACTOR).max(16.0) as u32;

        if new_w == cur_w && new_h == cur_h {
            // Can't shrink further
            break;
        }

        img = Cow::Owned(img.resize(new_w, new_h, image::imageops::FilterType::Lanczos3));
        resized = true;
        // Re-prepare pixels from resized image
        prepared = prepare_pixels(&img, output_format);
    }

    // Final fallback: return whatever we can at min quality at current size
    let fallback = encode_image_prepared(&prepared, &img, min_q, output_format, params, jpeg_exif)?;
    total_iterations += 1;
    let (w, h) = prepared.dimensions();
    Ok(EngineResult {
        data: fallback,
        width: w,
        height: h,
        quality_used: min_q as u32,
        iterations: total_iterations,
        resized_to_fit: resized,
    })
}

struct SearchResult {
    best: Option<(Vec<u8>, u8)>,
    iterations: u32,
}

#[allow(clippy::too_many_arguments)]
fn binary_search_quality(
    prepared: &PreparedPixels,
    img: &DynamicImage,
    lo_init: u8,
    hi_init: u8,
    target: usize,
    output_format: DetectedFormat,
    params: &CompressParams,
    jpeg_exif: Option<&[u8]>,
) -> Result<SearchResult, CompressError> {
    let mut lo = lo_init;
    let mut hi = hi_init;
    let mut best: Option<(Vec<u8>, u8)> = None;
    let mut iterations: u32 = 0;

    while lo <= hi && iterations < MAX_BINARY_SEARCH_ITERATIONS {
        let mid = lo + (hi - lo) / 2;
        let encoded = encode_image_prepared(prepared, img, mid, output_format, params, jpeg_exif)?;
        iterations += 1;

        if encoded.len() <= target {
            // Fits! Try higher quality
            best = Some((encoded, mid));
            if mid == hi {
                break;
            }
            lo = mid + 1;
        } else {
            // Too big — try lower quality
            if mid == lo {
                break;
            }
            hi = mid - 1;
        }
    }

    Ok(SearchResult { best, iterations })
}

// ─── Encoding ────────────────────────────────────────────────────────────────

/// Encode using a DynamicImage — used for single-shot paths where pixel
/// conversion overhead is negligible (called once, not in a loop).
fn encode_image(
    img: &DynamicImage,
    quality: u8,
    format: DetectedFormat,
    params: &CompressParams,
    jpeg_exif: Option<&[u8]>,
) -> Result<Vec<u8>, CompressError> {
    match format {
        DetectedFormat::Jpeg => encode_jpeg(img, quality, params, jpeg_exif),
        DetectedFormat::Png => encode_png(img, params),
        DetectedFormat::WebpLossless => encode_webp_lossless(img, params),
        DetectedFormat::WebpLossy => encode_webp_lossy(img, quality),
    }
}

/// Encode using pre-converted pixel data — used in binary search loops
/// to avoid redundant to_rgb8()/to_rgba8() conversions per iteration.
/// Falls back to DynamicImage for PNG (which doesn't participate in
/// quality-based binary search in practice).
fn encode_image_prepared(
    prepared: &PreparedPixels,
    img: &DynamicImage,
    quality: u8,
    format: DetectedFormat,
    params: &CompressParams,
    jpeg_exif: Option<&[u8]>,
) -> Result<Vec<u8>, CompressError> {
    match format {
        DetectedFormat::Jpeg => {
            if let PreparedPixels::Rgb {
                data,
                width,
                height,
            } = prepared
            {
                encode_jpeg_raw(data, *width, *height, quality, params, jpeg_exif)
            } else {
                encode_jpeg(img, quality, params, jpeg_exif)
            }
        }
        DetectedFormat::Png => encode_png(img, params),
        DetectedFormat::WebpLossless => {
            if let PreparedPixels::Rgba {
                data,
                width,
                height,
            } = prepared
            {
                encode_webp_lossless_raw(data, *width, *height)
            } else {
                encode_webp_lossless(img, params)
            }
        }
        DetectedFormat::WebpLossy => {
            if let PreparedPixels::Rgba {
                data,
                width,
                height,
            } = prepared
            {
                encode_webp_lossy_raw(data, *width, *height, quality)
            } else {
                encode_webp_lossy(img, quality)
            }
        }
    }
}

fn encode_jpeg(
    img: &DynamicImage,
    quality: u8,
    params: &CompressParams,
    jpeg_exif: Option<&[u8]>,
) -> Result<Vec<u8>, CompressError> {
    let rgb = img.to_rgb8();
    let (width, height) = rgb.dimensions();
    encode_jpeg_raw(rgb.as_raw(), width, height, quality, params, jpeg_exif)
}

/// JPEG encoding from pre-converted RGB8 pixel data.
fn encode_jpeg_raw(
    pixels: &[u8],
    width: u32,
    height: u32,
    quality: u8,
    params: &CompressParams,
    jpeg_exif: Option<&[u8]>,
) -> Result<Vec<u8>, CompressError> {
    let use_trellis = params.jpeg_trellis != 0;
    let progressive = params.jpeg_progressive != 0;

    let preset = match (progressive, use_trellis) {
        (true, true) => Preset::ProgressiveBalanced,
        (true, false) => Preset::ProgressiveBalanced,
        (false, true) => Preset::BaselineBalanced,
        (false, false) => Preset::BaselineFastest,
    };

    let chroma = match ChromaSubsampling::from_u32(params.jpeg_chroma_subsampling) {
        ChromaSubsampling::Yuv420 => Subsampling::S420,
        ChromaSubsampling::Yuv422 => Subsampling::S422,
        ChromaSubsampling::Yuv444 => Subsampling::S444,
    };

    let trellis = if use_trellis {
        TrellisConfig::default()
    } else {
        TrellisConfig::disabled()
    };

    let mut encoder = mozjpeg_rs::Encoder::new(preset)
        .quality(quality)
        .progressive(progressive)
        .subsampling(chroma)
        .trellis(trellis);

    if let Some(exif) = jpeg_exif {
        encoder = encoder.exif_data(exif.to_vec());
    }

    let data = encoder
        .encode_rgb(pixels, width, height)
        .map_err(|e| CompressError::EncodeError(format!("JPEG encode failed: {e}")))?;

    Ok(data)
}

fn encode_png(img: &DynamicImage, params: &CompressParams) -> Result<Vec<u8>, CompressError> {
    // Pre-allocate based on image size to reduce reallocation during encoding.
    let (w, h) = img.dimensions();
    let estimated = (w as usize * h as usize * 4) / 2;
    let mut buf = Vec::with_capacity(estimated.min(64 * 1024 * 1024));
    let mut cursor = Cursor::new(&mut buf);
    img.write_to(&mut cursor, ImageFormat::Png)
        .map_err(|e| CompressError::EncodeError(format!("PNG encode failed: {e}")))?;

    // Then optimize with oxipng
    let opt_level = oxipng::Options::from_preset(params.png_optimization_level.min(6) as u8);

    let optimized = oxipng::optimize_from_memory(&buf, &opt_level)
        .map_err(|e| CompressError::EncodeError(format!("PNG optimization failed: {e}")))?;

    Ok(optimized)
}

// ─── Utilities ───────────────────────────────────────────────────────────────

pub(crate) fn detect_format(data: &[u8]) -> Result<DetectedFormat, CompressError> {
    if data.len() < 4 {
        return Err(CompressError::DecodeError("Input too small".into()));
    }

    // JPEG: starts with FF D8 FF
    if data[0] == 0xFF && data[1] == 0xD8 && data[2] == 0xFF {
        return Ok(DetectedFormat::Jpeg);
    }

    // PNG: starts with 89 50 4E 47 (‰PNG)
    if data[0] == 0x89 && data[1] == 0x50 && data[2] == 0x4E && data[3] == 0x47 {
        return Ok(DetectedFormat::Png);
    }

    // WebP: starts with RIFF....WEBP — check VP8 chunk to distinguish lossy/lossless
    if data.len() >= 16 && data[0..4] == *b"RIFF" && data[8..12] == *b"WEBP" {
        // VP8L = lossless, VP8 (lossy) or VP8X (extended) = lossy
        if data.len() >= 16 && &data[12..16] == b"VP8L" {
            return Ok(DetectedFormat::WebpLossless);
        }
        return Ok(DetectedFormat::WebpLossy);
    }

    // GIF: starts with GIF87a or GIF89a
    if data.len() >= 6 && &data[0..3] == b"GIF" {
        // GIF input accepted — will be decoded by image crate and re-encoded
        // as JPEG (auto format defaults to JPEG for non-native formats)
        return Ok(DetectedFormat::Jpeg);
    }

    // BMP: starts with BM
    if data[0] == 0x42 && data[1] == 0x4D {
        return Ok(DetectedFormat::Jpeg);
    }

    // TIFF: starts with II (little-endian) or MM (big-endian)
    if (data[0] == 0x49 && data[1] == 0x49) || (data[0] == 0x4D && data[1] == 0x4D) {
        return Ok(DetectedFormat::Jpeg);
    }

    Err(CompressError::UnsupportedFormat(
        "Unsupported format. Supported inputs: JPEG, PNG, WebP, GIF, BMP, TIFF".into(),
    ))
}

fn resolve_output_format(params: &CompressParams, detected: DetectedFormat) -> DetectedFormat {
    match OutputFormat::from_u32(params.format) {
        OutputFormat::Auto => detected,
        OutputFormat::Jpeg => DetectedFormat::Jpeg,
        OutputFormat::Png => DetectedFormat::Png,
        OutputFormat::WebpLossless => DetectedFormat::WebpLossless,
        OutputFormat::WebpLossy => DetectedFormat::WebpLossy,
    }
}

fn apply_resize_constraints<'a>(
    img: &'a DynamicImage,
    max_width: u32,
    max_height: u32,
) -> Cow<'a, DynamicImage> {
    if max_width == 0 && max_height == 0 {
        return Cow::Borrowed(img);
    }

    let (orig_w, orig_h) = img.dimensions();
    let target_w = if max_width > 0 { max_width } else { orig_w };
    let target_h = if max_height > 0 { max_height } else { orig_h };

    if orig_w <= target_w && orig_h <= target_h {
        return Cow::Borrowed(img);
    }

    let scale_w = target_w as f64 / orig_w as f64;
    let scale_h = target_h as f64 / orig_h as f64;
    let scale = scale_w.min(scale_h);

    let new_w = ((orig_w as f64) * scale).round().max(1.0) as u32;
    let new_h = ((orig_h as f64) * scale).round().max(1.0) as u32;

    Cow::Owned(img.resize_exact(new_w, new_h, image::imageops::FilterType::Lanczos3))
}

// ─── WebP Encoding ───────────────────────────────────────────────────────────

fn encode_webp_lossless(
    img: &DynamicImage,
    _params: &CompressParams,
) -> Result<Vec<u8>, CompressError> {
    let rgba = img.to_rgba8();
    let (width, height) = rgba.dimensions();
    encode_webp_lossless_raw(rgba.as_raw(), width, height)
}

/// WebP lossless encoding from pre-converted RGBA8 pixel data.
fn encode_webp_lossless_raw(
    pixels: &[u8],
    width: u32,
    height: u32,
) -> Result<Vec<u8>, CompressError> {
    let mut buf = Vec::new();
    let encoder = image::codecs::webp::WebPEncoder::new_lossless(&mut buf);
    encoder
        .encode(pixels, width, height, image::ExtendedColorType::Rgba8)
        .map_err(|e| CompressError::EncodeError(format!("WebP encode failed: {e}")))?;
    Ok(buf)
}

/// Encode image as lossy WebP using the `webp` crate.
fn encode_webp_lossy(img: &DynamicImage, quality: u8) -> Result<Vec<u8>, CompressError> {
    let rgba = img.to_rgba8();
    let (width, height) = (rgba.width(), rgba.height());
    encode_webp_lossy_raw(rgba.as_raw(), width, height, quality)
}

/// WebP lossy encoding from pre-converted RGBA8 pixel data.
fn encode_webp_lossy_raw(
    pixels: &[u8],
    width: u32,
    height: u32,
    quality: u8,
) -> Result<Vec<u8>, CompressError> {
    let encoder = webp::Encoder::from_rgba(pixels, width, height);
    let mem = encoder.encode(quality as f32);
    Ok(mem.to_vec())
}

// ─── Probe: Quick Metadata Without Full Decode ───────────────────────────────

/// Information extracted from image header without decoding pixel data.
pub struct ProbeInfo {
    pub width: u32,
    pub height: u32,
    pub format: DetectedFormat,
    pub file_size: usize,
    pub has_exif: bool,
}

/// Read image metadata from bytes without decoding the full image.
/// Only reads headers — very fast even on large files.
pub fn probe_bytes(data: &[u8]) -> Result<ProbeInfo, CompressError> {
    let format = detect_format(data)?;

    // Use image crate's Reader for dimensions (reads header only)
    let cursor = Cursor::new(data);
    let reader = ImageReader::new(cursor)
        .with_guessed_format()
        .map_err(|e| CompressError::DecodeError(format!("Failed to read header: {e}")))?;

    let (width, height) = reader
        .into_dimensions()
        .map_err(|e| CompressError::DecodeError(format!("Failed to read dimensions: {e}")))?;

    // Simple EXIF detection: search for EXIF marker in JPEG (APP1 segment with "Exif\0\0")
    let has_exif = match format {
        DetectedFormat::Jpeg => detect_exif_jpeg(data),
        DetectedFormat::Png => detect_exif_png(data),
        DetectedFormat::WebpLossless | DetectedFormat::WebpLossy => false,
    };

    Ok(ProbeInfo {
        width,
        height,
        format,
        file_size: data.len(),
        has_exif,
    })
}

/// Detect EXIF in JPEG by parsing marker segments using length fields.
/// Only walks marker segments (not compressed data) to avoid false positives.
fn detect_exif_jpeg(data: &[u8]) -> bool {
    if data.len() < 4 || data[0] != 0xFF || data[1] != 0xD8 {
        return false;
    }

    let mut offset = 2usize;
    while offset + 4 <= data.len() {
        if data[offset] != 0xFF {
            break;
        }

        // Skip padding 0xFF bytes
        let mut marker_offset = offset + 1;
        while marker_offset < data.len() && data[marker_offset] == 0xFF {
            marker_offset += 1;
        }
        if marker_offset >= data.len() {
            break;
        }

        let marker = data[marker_offset];
        offset = marker_offset + 1;

        // SOS or EOI — no more metadata markers
        if marker == 0xDA || marker == 0xD9 {
            break;
        }

        // Standalone markers (no length field)
        if marker == 0x01 || (0xD0..=0xD7).contains(&marker) {
            continue;
        }

        // Read segment length
        if offset + 2 > data.len() {
            break;
        }
        let segment_len = u16::from_be_bytes([data[offset], data[offset + 1]]) as usize;
        if segment_len < 2 || offset + segment_len > data.len() {
            break;
        }

        // APP1 marker with Exif header?
        if marker == 0xE1 && segment_len >= 8 {
            let payload = &data[offset + 2..offset + segment_len];
            if payload.starts_with(b"Exif\0\0") {
                return true;
            }
        }

        offset += segment_len;
    }

    false
}

/// Detect EXIF in PNG by walking chunk structure (length + type pairs).
/// Avoids false positives from scanning compressed data.
fn detect_exif_png(data: &[u8]) -> bool {
    if data.len() < 12 {
        return false;
    }

    // Skip PNG signature (8 bytes)
    let mut offset = 8usize;
    while offset + 8 <= data.len() {
        let chunk_len = u32::from_be_bytes([
            data[offset],
            data[offset + 1],
            data[offset + 2],
            data[offset + 3],
        ]) as usize;
        let chunk_type = &data[offset + 4..offset + 8];

        if chunk_type == b"eXIf" {
            return true;
        }

        // IEND marks end of PNG
        if chunk_type == b"IEND" {
            break;
        }

        // Next chunk: length(4) + type(4) + data(chunk_len) + CRC(4)
        offset += 12 + chunk_len;
    }

    false
}

// ─── Benchmark: Quality Sweep ────────────────────────────────────────────────

/// Single data point from a benchmark sweep.
pub struct BenchmarkEntry {
    pub quality: u32,
    pub size_bytes: usize,
    pub ratio: f32,
    pub encode_ms: u32,
}

/// Full benchmark result.
pub struct BenchmarkInfo {
    pub original_size: usize,
    pub width: u32,
    pub height: u32,
    pub format: DetectedFormat,
    pub entries: Vec<BenchmarkEntry>,
    pub recommended_quality: u32,
}

/// Run a quality sweep: encode the image at multiple quality levels
/// and measure size + speed for each. Returns a table that developers
/// can use to choose the optimal quality for their use case.
///
/// Only meaningful for JPEG (quality affects output size).
/// For PNG, returns a single entry since quality doesn't apply.
pub fn benchmark_bytes(
    data: &[u8],
    params: &CompressParams,
) -> Result<BenchmarkInfo, CompressError> {
    let format = detect_format(data)?;
    let img =
        image::load_from_memory(data).map_err(|e| CompressError::DecodeError(e.to_string()))?;

    // Apply resize constraints so benchmark matches real output
    let img = apply_resize_constraints(&img, params.max_width, params.max_height);
    let (width, height) = img.dimensions();
    let original_size = data.len();

    let output_format = resolve_output_format(params, format);

    let quality_levels: Vec<u32> = match output_format {
        DetectedFormat::Jpeg | DetectedFormat::WebpLossy => {
            vec![95, 90, 85, 80, 75, 70, 60, 50, 40, 30, 20]
        }
        // PNG/WebP lossless: quality doesn't apply, just benchmark once
        _ => vec![0],
    };

    // Pre-convert pixels once for the entire sweep (avoids 11× redundant conversions).
    let prepared = prepare_pixels(&img, output_format);
    let mut entries = Vec::with_capacity(quality_levels.len());

    for &q in &quality_levels {
        let start = std::time::Instant::now();
        let encoded = encode_image_prepared(&prepared, &img, q as u8, output_format, params, None)?;
        let elapsed = start.elapsed().as_millis() as u32;

        entries.push(BenchmarkEntry {
            quality: q,
            size_bytes: encoded.len(),
            ratio: encoded.len() as f32 / original_size as f32,
            encode_ms: elapsed,
        });
    }

    // Find recommended quality: the "knee" of the curve.
    // Highest quality where size reduction per quality step is still > 2%.
    let recommended = find_recommended_quality(&entries, original_size);

    Ok(BenchmarkInfo {
        original_size,
        width,
        height,
        format,
        entries,
        recommended_quality: recommended,
    })
}

/// Find the "sweet spot" quality — where you get diminishing returns
/// from reducing quality further. Uses the elbow method.
pub(crate) fn find_recommended_quality(entries: &[BenchmarkEntry], original_size: usize) -> u32 {
    if entries.len() < 2 {
        return entries.first().map(|e| e.quality).unwrap_or(80);
    }

    // Score each quality level: ratio of quality to file size reduction.
    // We want the highest quality where we still get meaningful size savings.
    let mut best_q = entries[0].quality;
    let mut best_score = 0.0f32;

    for entry in entries {
        let reduction = 1.0 - (entry.size_bytes as f32 / original_size as f32);
        let quality_normalized = entry.quality as f32 / 100.0;

        // Score favors high quality + good reduction
        // Geometric mean ensures both matter
        let score = (quality_normalized * reduction).sqrt();

        if score > best_score {
            best_score = score;
            best_q = entry.quality;
        }
    }

    best_q
}

fn resolve_jpeg_exif_payload(
    input: &[u8],
    detected: DetectedFormat,
    output_format: DetectedFormat,
    params: &CompressParams,
) -> Result<Option<Vec<u8>>, CompressError> {
    if params.keep_metadata == 0 {
        return Ok(None);
    }

    match (detected, output_format) {
        (DetectedFormat::Jpeg, DetectedFormat::Jpeg) => Ok(extract_jpeg_exif_payload(input)),
        // Metadata preservation is only supported for JPEG→JPEG; for all other
        // format combinations silently skip rather than failing the operation.
        _ => Ok(None),
    }
}

/// Test-only wrappers that expose internal encoding functions so tests can
/// verify that the PreparedPixels path produces byte-identical output to
/// the original DynamicImage path.
#[cfg(test)]
pub(crate) mod tests_internal {
    use super::*;
    use crate::options::CompressParams;

    pub fn encode_jpeg_via_dynamic(
        img: &DynamicImage,
        quality: u8,
        params: &CompressParams,
        exif: Option<&[u8]>,
    ) -> Vec<u8> {
        encode_jpeg(img, quality, params, exif).unwrap()
    }

    pub fn encode_jpeg_via_raw(
        pixels: &[u8],
        width: u32,
        height: u32,
        quality: u8,
        params: &CompressParams,
        exif: Option<&[u8]>,
    ) -> Vec<u8> {
        encode_jpeg_raw(pixels, width, height, quality, params, exif).unwrap()
    }

    pub fn encode_webp_lossy_via_dynamic(img: &DynamicImage, quality: u8) -> Vec<u8> {
        encode_webp_lossy(img, quality).unwrap()
    }

    pub fn encode_webp_lossy_via_raw(
        pixels: &[u8],
        width: u32,
        height: u32,
        quality: u8,
    ) -> Vec<u8> {
        encode_webp_lossy_raw(pixels, width, height, quality).unwrap()
    }

    pub fn encode_webp_lossless_via_dynamic(img: &DynamicImage) -> Vec<u8> {
        let params = CompressParams::default();
        encode_webp_lossless(img, &params).unwrap()
    }

    pub fn encode_webp_lossless_via_raw(pixels: &[u8], width: u32, height: u32) -> Vec<u8> {
        encode_webp_lossless_raw(pixels, width, height).unwrap()
    }
}

fn extract_jpeg_exif_payload(data: &[u8]) -> Option<Vec<u8>> {
    if data.len() < 4 || data[0] != 0xFF || data[1] != 0xD8 {
        return None;
    }

    let mut offset = 2usize;
    while offset + 4 <= data.len() {
        if data[offset] != 0xFF {
            break;
        }

        let mut marker_offset = offset + 1;
        while marker_offset < data.len() && data[marker_offset] == 0xFF {
            marker_offset += 1;
        }
        if marker_offset >= data.len() {
            break;
        }

        let marker = data[marker_offset];
        offset = marker_offset + 1;

        if marker == 0xD9 || marker == 0xDA {
            break;
        }

        if marker == 0x01 || (0xD0..=0xD7).contains(&marker) {
            continue;
        }

        if offset + 2 > data.len() {
            break;
        }

        let segment_len = u16::from_be_bytes([data[offset], data[offset + 1]]) as usize;
        if segment_len < 2 || offset + segment_len > data.len() {
            break;
        }

        let segment = &data[offset + 2..offset + segment_len];
        if marker == 0xE1 && segment.starts_with(b"Exif\0\0") && segment.len() > 6 {
            return Some(segment[6..].to_vec());
        }

        offset += segment_len;
    }

    None
}
