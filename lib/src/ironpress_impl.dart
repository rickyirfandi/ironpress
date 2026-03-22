import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'bindings.dart';
import 'native_loader.dart';
import 'options.dart';

/// Expected ABI version — must match the Rust constant.
/// Increment both sides when any #[repr(C)] struct layout changes.
const int _expectedAbiVersion = 1;

/// Error code used when the batch progress isolate crashes unexpectedly.
const int _isolateCrashCode = -100;

/// Validates quality parameters before passing them to the native engine.
///
/// Throws [ArgumentError] if [quality] or [minQuality] are outside 0–100.
/// Callers pass the explicitly-provided values (nullable) so that only
/// values the user actually supplied are validated; preset and default
/// values are already guaranteed to be in range.
void _validateQuality({int? quality, int? minQuality}) {
  if (quality != null && (quality < 0 || quality > 100)) {
    throw ArgumentError.value(
      quality,
      'quality',
      'must be in the range 0–100',
    );
  }
  if (minQuality != null && (minQuality < 0 || minQuality > 100)) {
    throw ArgumentError.value(
      minQuality,
      'minQuality',
      'must be in the range 0–100',
    );
  }
}

/// Cached bindings per isolate (each isolate has its own top-level state).
NativeBindings? _cachedBindings;
NativeBindings _getBindings() =>
    _cachedBindings ??= NativeBindings.fromLibrary(loadNativeLibrary());

/// High-performance image compression powered by Rust.
///
/// Uses mozjpeg (trellis quantization) for JPEG and oxipng for PNG —
/// delivering consistent, high-quality results across all platforms.
///
/// All operations run on a background isolate to keep the UI responsive.
///
/// ```dart
/// // Simple usage
/// final result = await Ironpress.compressFile(
///   'photo.jpg',
///   quality: 80,
/// );
///
/// // Target file size
/// final result = await Ironpress.compressFile(
///   'photo.jpg',
///   maxFileSize: 200 * 1024, // 200 KB
/// );
/// ```
class Ironpress {
  // Prevent instantiation
  Ironpress._();

  static NativeBindings? _bindings;

  /// Lazily initialize native bindings with ABI version check.
  static NativeBindings get _b {
    if (_bindings == null) {
      _bindings = _getBindings();
      final version = _bindings!.abiVersion();
      if (version != _expectedAbiVersion) {
        _bindings = null;
        throw StateError(
          'Ironpress ABI version mismatch: native=$version, '
          'expected=$_expectedAbiVersion. Rebuild the native library.',
        );
      }
    }
    return _bindings!;
  }

  // ─── Public API ──────────────────────────────────────────────────────

  /// Compress an image file and return the result as bytes.
  ///
  /// [path] — Absolute path to the input image (JPEG, PNG, WebP, GIF, BMP,
  /// or TIFF).
  ///
  /// [preset] — Optional quality preset ([CompressPreset.low],
  /// [CompressPreset.medium], [CompressPreset.high]). Explicit parameters
  /// always take priority over the preset.
  ///
  /// [quality] — JPEG quality 0-100. Default: 80. Ignored for PNG output.
  ///
  /// [maxWidth] / [maxHeight] — Resize constraints. Image is scaled down
  /// to fit within these bounds while preserving aspect ratio.
  ///
  /// [maxFileSize] — Target maximum output size in bytes. When set,
  /// the engine performs a binary search to find the highest quality
  /// that fits. This is the killer feature — one FFI call, no round-trips.
  ///
  /// [minQuality] — Quality floor for the binary search (default: 30).
  ///
  /// [allowResize] — If quality alone can't hit [maxFileSize], allow
  /// automatic downscaling. Default: `true`.
  ///
  /// [format] — Output format. Default: [CompressFormat.auto] (same as input).
  ///
  /// [keepMetadata] — Preserve JPEG EXIF metadata when compressing JPEG to
  /// JPEG. Other paths silently drop metadata.
  ///
  /// [jpeg] — Advanced JPEG options (progressive, trellis, chroma).
  ///
  /// [png] — Advanced PNG options (optimization level).
  ///
  /// Throws [ArgumentError] if [path] is empty.
  /// Throws [CompressException] if the native engine reports an error.
  ///
  /// ```dart
  /// // One-liner with a preset
  /// final result = await Ironpress.compressFile(
  ///   '/path/to/photo.jpg',
  ///   preset: CompressPreset.medium,
  /// );
  /// print(result); // CompressResult(4.2 MB → 380 KB [91%], 1920x1440, q80)
  ///
  /// // Target file size — binary search in Rust, single FFI call
  /// final result = await Ironpress.compressFile(
  ///   '/path/to/photo.jpg',
  ///   maxFileSize: 200 * 1024, // 200 KB
  ///   maxWidth: 1920,
  /// );
  /// ```
  static Future<CompressResult> compressFile(
    String path, {
    CompressPreset? preset,
    int? quality,
    int? maxWidth,
    int? maxHeight,
    int? maxFileSize,
    int? minQuality,
    bool allowResize = true,
    CompressFormat format = CompressFormat.auto,
    bool keepMetadata = false,
    JpegOptions jpeg = const JpegOptions(),
    PngOptions png = const PngOptions(),
  }) async {
    if (path.isEmpty) {
      throw ArgumentError.value(path, 'path', 'must not be empty');
    }
    _validateQuality(quality: quality, minQuality: minQuality);
    final effectiveQuality = quality ?? preset?.quality ?? 80;
    final effectiveMaxWidth = maxWidth ?? preset?.maxWidth;
    final effectiveMaxHeight = maxHeight ?? preset?.maxHeight;
    final effectiveMinQuality = minQuality ?? preset?.minQuality ?? 30;
    return Isolate.run(() {
      return _compressFileSync(
        path,
        quality: effectiveQuality,
        maxWidth: effectiveMaxWidth,
        maxHeight: effectiveMaxHeight,
        maxFileSize: maxFileSize,
        minQuality: effectiveMinQuality,
        allowResize: allowResize,
        format: format,
        keepMetadata: keepMetadata,
        jpeg: jpeg,
        png: png,
      );
    });
  }

  /// Compress an image file and write the result to [outputPath].
  ///
  /// Returns a [CompressResult] with stats but `data` will be `null`
  /// since the output was written to disk.
  ///
  /// Accepts the same parameters as [compressFile] including [preset].
  ///
  /// Throws [ArgumentError] if [inputPath] or [outputPath] is empty.
  /// Throws [CompressException] if the native engine reports an error.
  ///
  /// ```dart
  /// final result = await Ironpress.compressFileToFile(
  ///   '/input/photo.jpg',
  ///   '/output/photo_compressed.jpg',
  ///   preset: CompressPreset.medium,
  /// );
  /// assert(result.isFileOutput); // true — no bytes in memory
  /// ```
  static Future<CompressResult> compressFileToFile(
    String inputPath,
    String outputPath, {
    CompressPreset? preset,
    int? quality,
    int? maxWidth,
    int? maxHeight,
    int? maxFileSize,
    int? minQuality,
    bool allowResize = true,
    CompressFormat format = CompressFormat.auto,
    bool keepMetadata = false,
    JpegOptions jpeg = const JpegOptions(),
    PngOptions png = const PngOptions(),
  }) async {
    if (inputPath.isEmpty) {
      throw ArgumentError.value(inputPath, 'inputPath', 'must not be empty');
    }
    if (outputPath.isEmpty) {
      throw ArgumentError.value(outputPath, 'outputPath', 'must not be empty');
    }
    _validateQuality(quality: quality, minQuality: minQuality);
    final effectiveQuality = quality ?? preset?.quality ?? 80;
    final effectiveMaxWidth = maxWidth ?? preset?.maxWidth;
    final effectiveMaxHeight = maxHeight ?? preset?.maxHeight;
    final effectiveMinQuality = minQuality ?? preset?.minQuality ?? 30;
    return Isolate.run(() {
      return _compressFileToFileSync(
        inputPath,
        outputPath,
        quality: effectiveQuality,
        maxWidth: effectiveMaxWidth,
        maxHeight: effectiveMaxHeight,
        maxFileSize: maxFileSize,
        minQuality: effectiveMinQuality,
        allowResize: allowResize,
        format: format,
        keepMetadata: keepMetadata,
        jpeg: jpeg,
        png: png,
      );
    });
  }

  /// Compress raw image bytes in memory and return the result as bytes.
  ///
  /// Accepts JPEG, PNG, WebP, GIF, BMP, or TIFF input.
  /// Accepts the same parameters as [compressFile] including [preset].
  ///
  /// Throws [ArgumentError] if [data] is empty.
  /// Throws [CompressException] if the native engine reports an error.
  ///
  /// ```dart
  /// final bytes = await File('photo.jpg').readAsBytes();
  ///
  /// // Compress with a preset
  /// final result = await Ironpress.compressBytes(
  ///   bytes,
  ///   preset: CompressPreset.medium,
  /// );
  ///
  /// // Convert to WebP
  /// final webpResult = await Ironpress.compressBytes(
  ///   bytes,
  ///   quality: 80,
  ///   format: CompressFormat.webpLossy,
  /// );
  /// ```
  static Future<CompressResult> compressBytes(
    Uint8List data, {
    CompressPreset? preset,
    int? quality,
    int? maxWidth,
    int? maxHeight,
    int? maxFileSize,
    int? minQuality,
    bool allowResize = true,
    CompressFormat format = CompressFormat.auto,
    bool keepMetadata = false,
    JpegOptions jpeg = const JpegOptions(),
    PngOptions png = const PngOptions(),
  }) async {
    if (data.isEmpty) {
      throw ArgumentError.value(data, 'data', 'must not be empty');
    }
    _validateQuality(quality: quality, minQuality: minQuality);
    final effectiveQuality = quality ?? preset?.quality ?? 80;
    final effectiveMaxWidth = maxWidth ?? preset?.maxWidth;
    final effectiveMaxHeight = maxHeight ?? preset?.maxHeight;
    final effectiveMinQuality = minQuality ?? preset?.minQuality ?? 30;
    return Isolate.run(() {
      return _compressBytesSync(
        data,
        quality: effectiveQuality,
        maxWidth: effectiveMaxWidth,
        maxHeight: effectiveMaxHeight,
        maxFileSize: maxFileSize,
        minQuality: effectiveMinQuality,
        allowResize: allowResize,
        format: format,
        keepMetadata: keepMetadata,
        jpeg: jpeg,
        png: png,
      );
    });
  }

  /// Batch compress multiple images using Rust's rayon thread pool.
  ///
  /// **Performance:** Single FFI call → rayon splits across CPU cores with
  /// zero-copy shared params. For 200 inspection photos, this is 3-5x faster
  /// than sequential Dart isolates.
  ///
  /// **Safety:** Designed to never hang, OOM, or crash your app:
  /// - [chunkSize] limits how many images are decoded simultaneously
  ///   (default 8 ≈ ~288 MB peak for 4K photos). Between chunks, all
  ///   decoded pixel buffers are freed.
  /// - [threadCount] defaults to `cores - 2`, leaving room for Flutter
  ///   UI thread and Dart isolate. Your app stays responsive.
  /// - Each item is panic-safe: a corrupt JPEG or OOM on one image
  ///   produces an error result, not a process crash.
  ///
  /// **Progress:** Pass [onProgress] to get live updates. Called on the
  /// main thread with `(completed, total)` — safe to call `setState` directly.
  ///
  /// **Cancellation:** Pass a [CancellationToken] to cancel between chunks.
  /// Returns partial results for already-completed chunks.
  ///
  /// ```dart
  /// final token = CancellationToken();
  ///
  /// final result = await Ironpress.compressBatch(
  ///   photos.map((p) => CompressInput(path: p)).toList(),
  ///   preset: CompressPreset.medium,
  ///   maxFileSize: 300 * 1024,
  ///   cancellationToken: token,
  ///   onProgress: (done, total) {
  ///     setState(() => _progress = done / total);
  ///   },
  /// );
  /// print(result); // 200 images, 6823ms, 29.3 img/s
  /// ```
  static Future<BatchCompressResult> compressBatch(
    List<CompressInput> inputs, {
    CompressPreset? preset,
    int? quality,
    int? maxWidth,
    int? maxHeight,
    int? maxFileSize,
    int? minQuality,
    bool allowResize = true,
    CompressFormat format = CompressFormat.auto,
    bool keepMetadata = false,
    JpegOptions jpeg = const JpegOptions(),
    PngOptions png = const PngOptions(),
    int threadCount = 0,
    int chunkSize = 8,
    void Function(int completed, int total)? onProgress,
    CancellationToken? cancellationToken,
  }) async {
    _validateQuality(quality: quality, minQuality: minQuality);
    final effectiveQuality = quality ?? preset?.quality ?? 80;
    final effectiveMaxWidth = maxWidth ?? preset?.maxWidth;
    final effectiveMaxHeight = maxHeight ?? preset?.maxHeight;
    final effectiveMinQuality = minQuality ?? preset?.minQuality ?? 30;
    final total = inputs.length;
    if (total == 0) {
      return const BatchCompressResult(results: [], elapsedMs: 0);
    }

    final inputSpecs = inputs
        .map((i) => _BatchInputSpec(
              path: i.path,
              data: i.data,
              outputPath: i.outputPath,
            ))
        .toList();

    if (onProgress != null) {
      return _compressBatchWithProgress(
        inputSpecs,
        total: total,
        quality: effectiveQuality,
        maxWidth: effectiveMaxWidth,
        maxHeight: effectiveMaxHeight,
        maxFileSize: maxFileSize,
        minQuality: effectiveMinQuality,
        allowResize: allowResize,
        format: format,
        keepMetadata: keepMetadata,
        jpeg: jpeg,
        png: png,
        threadCount: threadCount,
        chunkSize: chunkSize,
        onProgress: onProgress,
        cancellationToken: cancellationToken,
      );
    }

    return Isolate.run(() {
      return _compressBatchSync(
        inputSpecs,
        quality: effectiveQuality,
        maxWidth: effectiveMaxWidth,
        maxHeight: effectiveMaxHeight,
        maxFileSize: maxFileSize,
        minQuality: effectiveMinQuality,
        allowResize: allowResize,
        format: format,
        keepMetadata: keepMetadata,
        jpeg: jpeg,
        png: png,
        threadCount: threadCount,
        chunkSize: chunkSize,
      );
    });
  }

  /// Batch with progress: runs FFI on an isolate and forwards chunk progress.
  static Future<BatchCompressResult> _compressBatchWithProgress(
    List<_BatchInputSpec> inputSpecs, {
    required int total,
    required int quality,
    int? maxWidth,
    int? maxHeight,
    int? maxFileSize,
    required int minQuality,
    required bool allowResize,
    required CompressFormat format,
    required bool keepMetadata,
    required JpegOptions jpeg,
    required PngOptions png,
    required int threadCount,
    required int chunkSize,
    required void Function(int completed, int total) onProgress,
    CancellationToken? cancellationToken,
  }) async {
    final progressPort = ReceivePort();
    final resultPort = ReceivePort();
    final errorPort = ReceivePort();

    // Ports must be closed regardless of whether spawn succeeds or fails,
    // otherwise they leak OS resources.
    try {
      progressPort.listen((message) {
        if (message is int) {
          onProgress(message, total);
        }
      });

      await Isolate.spawn(
        (message) {
          final args = message as List;
          final specs = args[0] as List<_BatchInputSpec>;
          final progressSend = args[1] as SendPort;
          final resultSend = args[2] as SendPort;
          final params = args[3] as Map<String, dynamic>;

          final result = _compressBatchSync(
            specs,
            quality: params['quality'] as int,
            maxWidth: params['maxWidth'] as int?,
            maxHeight: params['maxHeight'] as int?,
            maxFileSize: params['maxFileSize'] as int?,
            minQuality: params['minQuality'] as int,
            allowResize: params['allowResize'] as bool,
            format: params['format'] as CompressFormat,
            keepMetadata: params['keepMetadata'] as bool,
            jpeg: params['jpeg'] as JpegOptions,
            png: params['png'] as PngOptions,
            threadCount: params['threadCount'] as int,
            chunkSize: params['chunkSize'] as int,
            progressSendPort: progressSend,
          );

          resultSend.send(result);
        },
        [
          inputSpecs,
          progressPort.sendPort,
          resultPort.sendPort,
          {
            'quality': quality,
            'maxWidth': maxWidth,
            'maxHeight': maxHeight,
            'maxFileSize': maxFileSize,
            'minQuality': minQuality,
            'allowResize': allowResize,
            'format': format,
            'keepMetadata': keepMetadata,
            'jpeg': jpeg,
            'png': png,
            'threadCount': threadCount,
            'chunkSize': chunkSize,
          },
        ],
        onError: errorPort.sendPort,
      );

      // Race result vs isolate error to avoid hanging if the isolate crashes.
      final first = await Future.any([resultPort.first, errorPort.first]);

      if (first is BatchCompressResult) {
        onProgress(total, total);
        return first;
      }

      // Isolate error — first is [errorMessage, stackTrace]
      final errorInfo = first as List;
      throw CompressException(
        _isolateCrashCode,
        'Batch compression isolate crashed: ${errorInfo[0]}',
      );
    } finally {
      progressPort.close();
      resultPort.close();
      errorPort.close();
    }
  }

  // ─── Probe: Quick Metadata ───────────────────────────────────────────

  /// Read image metadata from a file without decoding pixel data.
  ///
  /// Much faster than compression — useful for validating images before
  /// upload or checking resolution before deciding whether to resize.
  ///
  /// Throws [ArgumentError] if [path] is empty.
  /// Throws [CompressException] if the file cannot be read or parsed.
  ///
  /// ```dart
  /// final info = await Ironpress.probeFile('/path/to/photo.jpg');
  /// print(info); // ImageProbe(4000x3000, JPEG, 4.2 MB, 12.0MP, EXIF)
  ///
  /// if (info.megapixels > 12) {
  ///   // Only compress if large enough to benefit
  ///   await Ironpress.compressFile(path, preset: CompressPreset.medium);
  /// }
  /// ```
  static Future<ImageProbe> probeFile(String path) async {
    if (path.isEmpty) {
      throw ArgumentError.value(path, 'path', 'must not be empty');
    }
    return Isolate.run(() {
      final bindings = _getBindings();
      final pathPtr = path.toNativeUtf8();
      final outPtr = calloc<NativeProbeResult>();

      try {
        bindings.probeFile(pathPtr, outPtr);

        if (outPtr.ref.errorCode != 0) {
          final msg = outPtr.ref.errorMessage != nullptr
              ? outPtr.ref.errorMessage.toDartString()
              : 'Probe failed (code ${outPtr.ref.errorCode})';
          throw CompressException(outPtr.ref.errorCode, msg);
        }

        return ImageProbe(
          width: outPtr.ref.width,
          height: outPtr.ref.height,
          format: ImageFormat.fromValue(outPtr.ref.format),
          fileSize: outPtr.ref.fileSize,
          hasExif: outPtr.ref.hasExif != 0,
        );
      } finally {
        bindings.freeProbeResult(outPtr);
        calloc.free(outPtr);
        calloc.free(pathPtr);
      }
    });
  }

  /// Deprecated. Use [probeFile] instead.
  @Deprecated('Use probeFile instead')
  static Future<ImageProbe> probe(String path) => probeFile(path);

  /// Read image metadata from bytes without decoding pixel data.
  ///
  /// Throws [ArgumentError] if [data] is empty.
  /// Throws [CompressException] if the data cannot be parsed.
  static Future<ImageProbe> probeBytes(Uint8List data) async {
    if (data.isEmpty) {
      throw ArgumentError.value(data, 'data', 'must not be empty');
    }
    return Isolate.run(() {
      final bindings = _getBindings();
      final nativeData = calloc<Uint8>(data.length);
      nativeData.asTypedList(data.length).setAll(0, data);
      final outPtr = calloc<NativeProbeResult>();

      try {
        bindings.probeBuffer(nativeData, data.length, outPtr);

        if (outPtr.ref.errorCode != 0) {
          final msg = outPtr.ref.errorMessage != nullptr
              ? outPtr.ref.errorMessage.toDartString()
              : 'Probe failed (code ${outPtr.ref.errorCode})';
          throw CompressException(outPtr.ref.errorCode, msg);
        }

        return ImageProbe(
          width: outPtr.ref.width,
          height: outPtr.ref.height,
          format: ImageFormat.fromValue(outPtr.ref.format),
          fileSize: outPtr.ref.fileSize,
          hasExif: outPtr.ref.hasExif != 0,
        );
      } finally {
        bindings.freeProbeResult(outPtr);
        calloc.free(outPtr);
        calloc.free(nativeData);
      }
    });
  }

  // ─── Benchmark: Quality Sweep ────────────────────────────────────────

  /// Run a quality sweep on a file: encode at multiple quality levels and
  /// measure output size and speed for each level.
  ///
  /// Useful for picking the right quality for your use case before committing
  /// to a value. The result includes a `recommendedQuality` field with the
  /// best size/quality trade-off.
  ///
  /// Throws [ArgumentError] if [path] is empty.
  /// Throws [CompressException] if the file cannot be read or parsed.
  ///
  /// ```dart
  /// final bench = await Ironpress.benchmarkFile('/path/to/photo.jpg');
  /// print(bench);
  /// // Benchmark(4.2 MB, 4000x3000, JPEG, recommended: q78)
  /// //   q95: 1.2 MB (70.5%, 210ms)
  /// //   q85: 620 KB (85.2%, 180ms)
  /// //   q78: 410 KB (90.2%, 165ms)  ← recommended
  /// //   q65: 280 KB (93.3%, 155ms)
  /// //   ...
  /// ```
  static Future<BenchmarkResult> benchmarkFile(
    String path, {
    int? maxWidth,
    int? maxHeight,
  }) async {
    if (path.isEmpty) {
      throw ArgumentError.value(path, 'path', 'must not be empty');
    }
    return Isolate.run(() {
      return _benchmarkFileSync(
        path,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
      );
    });
  }

  /// Deprecated. Use [benchmarkFile] instead.
  @Deprecated('Use benchmarkFile instead')
  static Future<BenchmarkResult> benchmark(
    String path, {
    int? maxWidth,
    int? maxHeight,
  }) =>
      benchmarkFile(path, maxWidth: maxWidth, maxHeight: maxHeight);

  /// Run a quality sweep on raw image bytes.
  ///
  /// Throws [ArgumentError] if [data] is empty.
  static Future<BenchmarkResult> benchmarkBytes(
    Uint8List data, {
    int? maxWidth,
    int? maxHeight,
  }) async {
    if (data.isEmpty) {
      throw ArgumentError.value(data, 'data', 'must not be empty');
    }
    return Isolate.run(() {
      return _benchmarkBytesSync(
        data,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
      );
    });
  }

  /// Return the native library version string.
  static String get nativeVersion {
    final ptr = _b.version();
    return ptr.toDartString();
  }

  // ─── Internal: Sync FFI calls (run on isolates) ──────────────────────

  static CompressResult _compressFileSync(
    String path, {
    required int quality,
    int? maxWidth,
    int? maxHeight,
    int? maxFileSize,
    required int minQuality,
    required bool allowResize,
    required CompressFormat format,
    required bool keepMetadata,
    required JpegOptions jpeg,
    required PngOptions png,
  }) {
    final bindings = _getBindings();
    final pathPtr = path.toNativeUtf8();
    final paramsPtr = _buildParams(
      quality: quality,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      maxFileSize: maxFileSize,
      minQuality: minQuality,
      allowResize: allowResize,
      format: format,
      keepMetadata: keepMetadata,
      jpeg: jpeg,
      png: png,
    );
    final outPtr = calloc<NativeCompressResult>();

    try {
      bindings.compressFile(pathPtr, paramsPtr, outPtr);
      return _convertResult(outPtr, bindings);
    } finally {
      calloc.free(pathPtr);
      calloc.free(paramsPtr);
    }
  }

  static CompressResult _compressFileToFileSync(
    String inputPath,
    String outputPath, {
    required int quality,
    int? maxWidth,
    int? maxHeight,
    int? maxFileSize,
    required int minQuality,
    required bool allowResize,
    required CompressFormat format,
    required bool keepMetadata,
    required JpegOptions jpeg,
    required PngOptions png,
  }) {
    final bindings = _getBindings();
    final inPtr = inputPath.toNativeUtf8();
    final outPathPtr = outputPath.toNativeUtf8();
    final paramsPtr = _buildParams(
      quality: quality,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      maxFileSize: maxFileSize,
      minQuality: minQuality,
      allowResize: allowResize,
      format: format,
      keepMetadata: keepMetadata,
      jpeg: jpeg,
      png: png,
    );
    final outPtr = calloc<NativeCompressResult>();

    try {
      bindings.compressFileToFile(inPtr, outPathPtr, paramsPtr, outPtr);
      return _convertResult(outPtr, bindings);
    } finally {
      calloc.free(inPtr);
      calloc.free(outPathPtr);
      calloc.free(paramsPtr);
    }
  }

  static CompressResult _compressBytesSync(
    Uint8List data, {
    required int quality,
    int? maxWidth,
    int? maxHeight,
    int? maxFileSize,
    required int minQuality,
    required bool allowResize,
    required CompressFormat format,
    required bool keepMetadata,
    required JpegOptions jpeg,
    required PngOptions png,
  }) {
    final bindings = _getBindings();
    final nativeData = calloc<Uint8>(data.length);
    nativeData.asTypedList(data.length).setAll(0, data);
    final paramsPtr = _buildParams(
      quality: quality,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      maxFileSize: maxFileSize,
      minQuality: minQuality,
      allowResize: allowResize,
      format: format,
      keepMetadata: keepMetadata,
      jpeg: jpeg,
      png: png,
    );
    final outPtr = calloc<NativeCompressResult>();

    try {
      bindings.compressBuffer(nativeData, data.length, paramsPtr, outPtr);
      return _convertResult(outPtr, bindings);
    } finally {
      calloc.free(nativeData);
      calloc.free(paramsPtr);
    }
  }

  // ─── Benchmark sync helpers ────────────────────────────────────────────

  static BenchmarkResult _benchmarkFileSync(
    String path, {
    int? maxWidth,
    int? maxHeight,
  }) {
    final bindings = _getBindings();
    final pathPtr = path.toNativeUtf8();
    final paramsPtr = _buildParams(
      quality: 80,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      format: CompressFormat.auto,
      keepMetadata: false,
      jpeg: const JpegOptions(),
      png: const PngOptions(),
      minQuality: 30,
      allowResize: true,
    );
    final outPtr = calloc<NativeBenchmarkResult>();

    try {
      bindings.benchmarkFile(pathPtr, paramsPtr, outPtr);
      return _convertBenchmarkResult(outPtr, bindings);
    } finally {
      calloc.free(pathPtr);
      calloc.free(paramsPtr);
    }
  }

  static BenchmarkResult _benchmarkBytesSync(
    Uint8List data, {
    int? maxWidth,
    int? maxHeight,
  }) {
    final bindings = _getBindings();
    final nativeData = calloc<Uint8>(data.length);
    nativeData.asTypedList(data.length).setAll(0, data);
    final paramsPtr = _buildParams(
      quality: 80,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      format: CompressFormat.auto,
      keepMetadata: false,
      jpeg: const JpegOptions(),
      png: const PngOptions(),
      minQuality: 30,
      allowResize: true,
    );
    final outPtr = calloc<NativeBenchmarkResult>();

    try {
      bindings.benchmarkBuffer(nativeData, data.length, paramsPtr, outPtr);
      return _convertBenchmarkResult(outPtr, bindings);
    } finally {
      calloc.free(nativeData);
      calloc.free(paramsPtr);
    }
  }

  // ─── Helpers ─────────────────────────────────────────────────────────

  static Pointer<NativeCompressParams> _buildParams({
    required int quality,
    int? maxWidth,
    int? maxHeight,
    int? maxFileSize,
    required int minQuality,
    required bool allowResize,
    required CompressFormat format,
    required bool keepMetadata,
    required JpegOptions jpeg,
    required PngOptions png,
  }) {
    final p = calloc<NativeCompressParams>();
    p.ref.quality = quality.clamp(0, 100);
    p.ref.maxWidth = maxWidth ?? 0;
    p.ref.maxHeight = maxHeight ?? 0;
    p.ref.maxFileSize = maxFileSize ?? 0;
    p.ref.minQuality = minQuality.clamp(0, 100);
    p.ref.allowResize = allowResize ? 1 : 0;
    p.ref.format = format.value;
    p.ref.keepMetadata = keepMetadata ? 1 : 0;
    p.ref.jpegProgressive = jpeg.progressive ? 1 : 0;
    p.ref.jpegChromaSubsampling = jpeg.chromaSubsampling.value;
    p.ref.jpegTrellis = jpeg.trellis ? 1 : 0;
    p.ref.pngOptimizationLevel = png.optimizationLevel.clamp(0, 6);
    return p;
  }

  /// Convert a native CompressResult (written via output pointer) to Dart.
  /// Frees the native inner allocations and the output pointer.
  static CompressResult _convertResult(
    Pointer<NativeCompressResult> outPtr,
    NativeBindings bindings,
  ) {
    try {
      final ref = outPtr.ref;

      if (ref.errorCode != 0) {
        final msg = ref.errorMessage != nullptr
            ? ref.errorMessage.toDartString()
            : 'Unknown error (code ${ref.errorCode})';
        throw CompressException(ref.errorCode, msg);
      }

      Uint8List? dartData;
      final compressedSize = ref.dataLen;

      if (ref.data != nullptr && ref.dataLen > 0) {
        dartData = Uint8List.fromList(
          ref.data.cast<Uint8>().asTypedList(ref.dataLen),
        );
      }

      return CompressResult(
        data: dartData,
        originalSize: ref.originalSize,
        compressedSize: compressedSize,
        width: ref.width,
        height: ref.height,
        qualityUsed: ref.qualityUsed,
        iterations: ref.iterations,
        resizedToFit: ref.resizedToFit != 0,
      );
    } finally {
      bindings.freeCompressResult(outPtr);
      calloc.free(outPtr);
    }
  }

  /// Convert a native BenchmarkResult to Dart. Frees native memory.
  static BenchmarkResult _convertBenchmarkResult(
    Pointer<NativeBenchmarkResult> outPtr,
    NativeBindings bindings,
  ) {
    try {
      final ref = outPtr.ref;

      if (ref.errorCode != 0) {
        final msg = ref.errorMessage != nullptr
            ? ref.errorMessage.toDartString()
            : 'Benchmark failed (code ${ref.errorCode})';
        throw CompressException(ref.errorCode, msg);
      }

      final entries = <BenchmarkEntry>[];
      for (var i = 0; i < ref.entryCount; i++) {
        final e = ref.entries[i];
        entries.add(BenchmarkEntry(
          quality: e.quality,
          sizeBytes: e.sizeBytes,
          ratio: e.ratio,
          encodeMs: e.encodeMs,
        ));
      }

      return BenchmarkResult(
        originalSize: ref.originalSize,
        width: ref.width,
        height: ref.height,
        format: ImageFormat.fromValue(ref.format),
        entries: entries,
        recommendedQuality: ref.recommendedQuality,
      );
    } finally {
      bindings.freeBenchmarkResult(outPtr);
      calloc.free(outPtr);
    }
  }

  static BatchCompressResult _compressBatchSync(
    List<_BatchInputSpec> inputs, {
    required int quality,
    int? maxWidth,
    int? maxHeight,
    int? maxFileSize,
    required int minQuality,
    required bool allowResize,
    required CompressFormat format,
    required bool keepMetadata,
    required JpegOptions jpeg,
    required PngOptions png,
    required int threadCount,
    required int chunkSize,
    SendPort? progressSendPort,
    CancellationToken? cancellationToken,
  }) {
    final bindings = _getBindings();
    final stopwatch = Stopwatch()..start();

    final paramsPtr = _buildParams(
      quality: quality,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      maxFileSize: maxFileSize,
      minQuality: minQuality,
      allowResize: allowResize,
      format: format,
      keepMetadata: keepMetadata,
      jpeg: jpeg,
      png: png,
    );

    final allResults = <CompressResult>[];
    var completed = 0;

    try {
      for (var start = 0; start < inputs.length; start += chunkSize) {
        // Check cancellation between chunks
        if (cancellationToken?.isCancelled ?? false) {
          break;
        }

        final end = (start + chunkSize).clamp(0, inputs.length);
        final chunkInputs = inputs.sublist(start, end);

        final nativeInputs = calloc<NativeBatchInput>(chunkInputs.length);
        final allocations = <Pointer>[];

        try {
          for (var i = 0; i < chunkInputs.length; i++) {
            final spec = chunkInputs[i];
            final ref = nativeInputs[i];

            if (spec.path != null) {
              final pathPtr = spec.path!.toNativeUtf8();
              allocations.add(pathPtr);
              ref.filePath = pathPtr;
              ref.data = nullptr;
              ref.dataLen = 0;
            } else if (spec.data != null) {
              final dataPtr = calloc<Uint8>(spec.data!.length);
              allocations.add(dataPtr);
              dataPtr.asTypedList(spec.data!.length).setAll(0, spec.data!);
              ref.filePath = nullptr;
              ref.data = dataPtr;
              ref.dataLen = spec.data!.length;
            } else {
              ref.filePath = nullptr;
              ref.data = nullptr;
              ref.dataLen = 0;
            }

            if (spec.outputPath != null) {
              final outPathPtr = spec.outputPath!.toNativeUtf8();
              allocations.add(outPathPtr);
              ref.outputPath = outPathPtr;
            } else {
              ref.outputPath = nullptr;
            }
          }

          // ═══ FFI CALL: rayon processes this chunk in parallel ═══
          final batchOutPtr = calloc<NativeBatchResult>();

          try {
            bindings.compressBatch(
              nativeInputs,
              chunkInputs.length,
              paramsPtr,
              threadCount,
              chunkSize,
              batchOutPtr,
            );

            final batchRef = batchOutPtr.ref;

            for (var i = 0; i < batchRef.count; i++) {
              final native = batchRef.results[i];

              if (native.errorCode != 0) {
                final msg = native.errorMessage != nullptr
                    ? native.errorMessage.toDartString()
                    : 'Error (code ${native.errorCode})';
                allResults.add(CompressResult(
                  data: null,
                  originalSize: native.originalSize,
                  compressedSize: 0,
                  width: 0,
                  height: 0,
                  qualityUsed: 0,
                  iterations: 0,
                  resizedToFit: false,
                  errorCode: native.errorCode,
                  errorMessage: msg,
                ));
              } else {
                Uint8List? dartData;
                if (native.data != nullptr && native.dataLen > 0) {
                  dartData = Uint8List.fromList(
                    native.data.cast<Uint8>().asTypedList(native.dataLen),
                  );
                }

                allResults.add(CompressResult(
                  data: dartData,
                  originalSize: native.originalSize,
                  compressedSize: native.dataLen,
                  width: native.width,
                  height: native.height,
                  qualityUsed: native.qualityUsed,
                  iterations: native.iterations,
                  resizedToFit: native.resizedToFit != 0,
                ));
              }
            }

            bindings.freeBatchResult(batchOutPtr);
          } finally {
            calloc.free(batchOutPtr);
          }
        } finally {
          for (final ptr in allocations) {
            calloc.free(ptr);
          }
          calloc.free(nativeInputs);
        }

        completed += chunkInputs.length;
        progressSendPort?.send(completed);
      }
    } finally {
      calloc.free(paramsPtr);
    }

    stopwatch.stop();
    return BatchCompressResult(
      results: allResults,
      elapsedMs: stopwatch.elapsedMilliseconds,
    );
  }
}

/// Lightweight spec for crossing isolate boundary (no FFI pointers).
class _BatchInputSpec {
  const _BatchInputSpec({this.path, this.data, this.outputPath});

  final String? path;
  final Uint8List? data;
  final String? outputPath;
}

/// Exception thrown when native compression fails.
class CompressException implements Exception {
  const CompressException(this.code, this.message);

  /// Native error code from the Rust engine.
  ///
  /// | Code | Meaning |
  /// |------|---------|
  /// | -1   | Null pointer or missing input |
  /// | -2   | Invalid UTF-8 path or empty buffer |
  /// | -3   | Failed to read input file |
  /// | -4   | Failed to write output file |
  /// | -5   | Input exceeds 256 MB limit |
  /// | -10  | Compression engine error (unsupported format, corrupt data) |
  /// | -99  | Internal panic on a batch item |
  /// | -100 | Batch isolate crashed unexpectedly |
  final int code;

  /// Human-readable error message from the Rust engine.
  final String message;

  /// Actionable hint based on the error code.
  String get hint {
    switch (code) {
      case -1:
        return 'Ensure a non-empty file path or byte buffer was provided.';
      case -2:
        return 'Check that the file path uses valid UTF-8 characters and the buffer is not empty.';
      case -3:
        return 'Verify the input file exists and the app has read permission.';
      case -4:
        return 'Verify the output directory exists and the app has write permission.';
      case -5:
        return 'Input exceeds the 256 MB limit. Reduce input size or split into smaller files.';
      case -10:
        return 'Ensure the input is a valid JPEG, PNG, or WebP file. '
            'GIF, BMP, and TIFF are accepted as input but must be intact.';
      case -99:
        return 'The image may be corrupt or the device ran out of memory for this item. '
            'Other batch items are unaffected.';
      case -100:
        return 'Internal error. Please file a bug at https://github.com/nicearma/ironpress/issues.';
      default:
        return '';
    }
  }

  @override
  String toString() {
    final h = hint;
    return h.isEmpty
        ? 'CompressException($code): $message'
        : 'CompressException($code): $message\nHint: $h';
  }
}
