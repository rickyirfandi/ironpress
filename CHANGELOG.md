## 0.1.0

**Initial release.**

### Compression engines
- JPEG compression via [mozjpeg-rs](https://crates.io/crates/mozjpeg-rs) — pure Rust, trellis quantization, progressive encoding
- PNG optimization via [oxipng](https://crates.io/crates/oxipng) — pure Rust, lossless, multithreaded
- WebP support (lossy + lossless) via the `webp` crate

### API
- `Ironpress.compressFile` — compress a file path, return bytes + stats
- `Ironpress.compressFileToFile` — compress file-to-file with no in-memory byte copy
- `Ironpress.compressBytes` — compress an in-memory `Uint8List`
- `Ironpress.compressBatch` — parallel batch compression with progress callbacks and cancellation support
- `Ironpress.probeFile` / `Ironpress.probeBytes` — read image dimensions and format without decoding pixels
- `Ironpress.benchmarkFile` / `Ironpress.benchmarkBytes` — sweep quality levels to generate a compression/size curve
- `Ironpress.nativeVersion` — verify the loaded native library version

### Robustness
- `ReceivePort`s in `compressBatch` with progress callbacks are always closed in a `finally` block
- `compressFile`, `compressFileToFile`, `compressBytes`, and `compressBatch` throw `ArgumentError` immediately when `quality` or `minQuality` is outside 0–100
- `JpegOptions`, `PngOptions`, and `CompressPreset` are annotated `@immutable`

### Example app
- Comprehensive example with 9 demo screens covering 100% of the public API
- Visual before/after comparisons, interactive sliders, bar charts, and progress indicators
- Screens: basic compression, quality presets, target file size, format comparison, batch processing, probe metadata, benchmark, advanced options (JPEG/PNG), file I/O

### Key features
- **Binary-search target file size** (`maxFileSize`): the engine loops entirely in Rust — single FFI call, no round-trips
- **Auto-resize fallback**: if quality alone can't reach `maxFileSize`, image is downscaled and retried
- **Aspect-ratio-preserving resize** via `maxWidth` / `maxHeight`
- **Batch panic safety**: one corrupt image never crashes the batch; other items continue normally
- **ABI version checking**: prevents stale native library mismatches from causing silent bugs
- **EXIF metadata preservation** for JPEG→JPEG (`keepMetadata: true`)
- **Format conversion**: auto-detect input, choose output format (JPEG / PNG / WebP lossy / WebP lossless)

### Platform support
- Android: `arm64-v8a`, `armeabi-v7a`, `x86`, `x86_64` (precompiled `.so`)
- iOS: device + simulator (precompiled `xcframework`)
- Windows: `x86_64` (precompiled `.dll`)
- Linux: `x86_64` (precompiled `.so`)
- macOS: `arm64` + `x86_64` universal (precompiled `.dylib`)
- Web: not supported (`dart:ffi` is unavailable on Flutter Web)
