<p align="center">
  <img src="https://raw.githubusercontent.com/rickyirfandi/ironpress/master/asset/ironpress.png" alt="ironpress logo" width="200"/>
</p>

<h1 align="center">ironpress</h1>

<p align="center">
  <strong>Rust-powered image compression for Flutter.</strong>
</p>

<p align="center">
  <a href="https://pub.dev/packages/ironpress"><img src="https://img.shields.io/pub/v/ironpress.svg" alt="pub package"></a>
  <a href="https://pub.dev/packages/ironpress/score"><img src="https://img.shields.io/pub/likes/ironpress" alt="pub likes"></a>
  <a href="https://pub.dev/packages/ironpress/score"><img src="https://img.shields.io/pub/points/ironpress" alt="pub points"></a>
  <a href="https://github.com/rickyirfandi/ironpress/actions/workflows/test.yml"><img src="https://github.com/rickyirfandi/ironpress/actions/workflows/test.yml/badge.svg" alt="tests"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="license"></a>
  <img src="https://img.shields.io/badge/platforms-android%20%7C%20iOS%20%7C%20windows-blue" alt="platforms">
</p>

---

ironpress compresses JPEG, PNG, and WebP images using mozjpeg, oxipng, and libwebp, compiled as native Rust libraries. mozjpeg and oxipng are **state-of-the-art compression engines** trusted by major CDNs and tech companies. All encoding runs in a single FFI call with no platform API dependencies, producing byte-identical output on every device. Accepts JPEG, PNG, WebP, GIF, BMP, and TIFF as input.

## Features

- **mozjpeg JPEG compression** with trellis quantization (25-35% smaller than standard encoders)
- **oxipng PNG optimization**, lossless and multithreaded
- **WebP lossy and lossless** encoding
- **Target file size** in a single FFI call (binary search runs entirely in Rust, zero round-trips)
- **Parallel batch compression** via Rayon with work-stealing across all cores
- **Byte-identical output** on Android, iOS, and Windows
- **Progress callbacks** and **cancellation tokens** for batch operations
- **Quality presets** (low, medium, high) for common use cases
- **Image probe** reads dimensions, format, and EXIF presence without decoding pixels
- **Quality benchmark sweep** to find optimal compression settings
- **EXIF metadata preservation** for JPEG-to-JPEG output
- **Panic-safe batch processing** (one corrupt image never kills the batch)

## Platform Support

| Platform | Architectures | Status |
|---|---|---|
| Android | arm64, armv7, x86_64 | Prebuilt |
| iOS | arm64 (device + simulator) | Prebuilt |
| Windows | x86_64 | Prebuilt |
| macOS | arm64, x86_64 | Build from source |
| Linux | x86_64 | Build from source |

Web is not supported (dart:ffi is unavailable on Flutter Web).

## Getting Started

### Installation

```yaml
dependencies:
  ironpress: ^0.1.0
```

### Basic Usage

```dart
import 'package:ironpress/ironpress.dart';

final result = await Ironpress.compressFile(
  'photo.jpg',
  quality: 80,
);
print(result);
// CompressResult(4.2 MB -> 380.0 KB [91.0%], 4000x3000, q80, 1iter)
```

No ProGuard or R8 rules required. ironpress loads native libraries via dart:ffi with no Java or Kotlin code.

## Usage

### Target File Size

Pass `maxFileSize` and the engine handles the entire binary search in Rust with no round-trips to Dart.

```dart
final result = await Ironpress.compressFile(
  'photo.jpg',
  maxFileSize: 200 * 1024, // 200 KB
);
print('Quality: ${result.qualityUsed}, Iterations: ${result.iterations}');
```

### Batch Compression

Compress entire galleries in parallel across all available cores. Progress callbacks and cancellation are built in.

```dart
final token = CancellationToken();

final batch = await Ironpress.compressBatch(
  photos.map((p) => CompressInput(path: p)).toList(),
  maxFileSize: 300 * 1024,
  maxWidth: 1920,
  threadCount: 4,
  onProgress: (done, total) => setState(() => progress = done / total),
  cancellationToken: token,
);

print(batch);
// BatchCompressResult(198/200 ok, 2 failed, 6823ms, 29.3 img/s, 4.1 MB/s)
```

### Quality Presets

Built-in presets for common use cases.

```dart
final result = await Ironpress.compressFile(
  'photo.jpg',
  preset: CompressPreset.medium, // q80, max 1920px
);
```

## Benchmarks

Measured on a 4MP JPEG (3264x2448, 4.2 MB) on Android arm64:

| Scenario | Result |
|---|---|
| Output size at q80 | 410 KB (90% reduction) |
| Output size at q75 | 340 KB (92% reduction) |
| Single image compression | ~180 ms |
| Target size to 200 KB | Single FFI call |
| Batch 10 images (parallel) | ~1.1 s |

mozjpeg's trellis quantization produces 25-35% smaller files at equivalent visual quality compared to standard libjpeg encoders.

## Advanced

### JPEG Options

```dart
final result = await Ironpress.compressFile(
  'photo.jpg',
  quality: 85,
  jpeg: const JpegOptions(
    progressive: true,
    trellis: true,
    chromaSubsampling: ChromaSubsampling.yuv420,
  ),
);
```

### Metadata Handling

`keepMetadata: true` preserves EXIF data for JPEG-to-JPEG output. When converting to PNG or WebP, metadata is silently dropped. The flag is always safe to pass.

### Diagnostics

```dart
// Read image metadata without decoding pixels
final probe = await Ironpress.probeFile('photo.jpg');
print(probe); // ImageProbe(3264x2448, JPEG, 4.2 MB, 7.99 MP)

// Find the optimal quality setting for your image
final bench = await Ironpress.benchmarkFile('photo.jpg');
print(bench.recommendedQuality); // e.g., 82
for (final entry in bench.entries) {
  print(entry); // q95: 520 KB (12.4%, 45ms)
}
```

## Size Impact

| What | Size |
|---|---|
| Per-platform native library | ~2-3 MB |
| App download increase (Play Store, arm64) | ~2 MB |
| pub.dev package (Android + Windows) | ~7-9 MB |

Android App Bundles automatically include only the ABI matching the user's device.

## API Reference

Full API documentation is available on [pub.dev](https://pub.dev/documentation/ironpress/latest/).

- `Ironpress.compressFile()` - Compress a file, return bytes + stats
- `Ironpress.compressFileToFile()` - Compress file to file on disk
- `Ironpress.compressBytes()` - Compress in-memory bytes
- `Ironpress.compressBatch()` - Parallel batch compression
- `Ironpress.probeFile()` / `probeBytes()` - Read image metadata without decoding
- `Ironpress.benchmarkFile()` / `benchmarkBytes()` - Quality sweep across 9 levels

## Migrating from flutter_image_compress

```dart
// Before
final result = await FlutterImageCompress.compressWithFile(
  file.path,
  minWidth: 1920,
  minHeight: 1080,
  quality: 80,
);

// After
final result = await Ironpress.compressFile(
  file.path,
  maxWidth: 1920,
  maxHeight: 1080,
  quality: 80,
);
final bytes = result.data; // Same Uint8List
```

## Building from Source

This release ships prebuilt Android, iOS, and Windows binaries. macOS and Linux require building from source.

```bash
# Prerequisites
cargo install cargo-ndk
rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android

# Build Android
cd rust
cargo ndk --target aarch64-linux-android --platform 21 build --release
cargo ndk --target armv7-linux-androideabi --platform 21 build --release
cargo ndk --target x86_64-linux-android --platform 21 build --release

# Build Windows
cargo build --release
```

<details>
<summary><strong>Error Codes</strong></summary>

| Code | Meaning |
|---|---|
| `-1` | Null pointer or missing input (no file path or data) |
| `-2` | Invalid UTF-8 in path or empty input buffer |
| `-3` | Failed to read input file |
| `-4` | Failed to write output file |
| `-5` | Input too large (exceeds 256 MB limit) |
| `-10` | Compression engine error (decode failure, unsupported format) |
| `-99` | Internal panic during batch item (OOM or corrupt image, other items unaffected) |
| `-100` | Batch isolate crashed unexpectedly |

</details>

## Contributing

Contributions are welcome. Please open an issue before submitting a pull request.

## License

MIT License. See [LICENSE](LICENSE) for details.

Rust compression engines: [mozjpeg-rs](https://crates.io/crates/mozjpeg-rs) (BSD-3), [oxipng](https://crates.io/crates/oxipng) (MIT).
