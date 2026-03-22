# ironpress

[![pub package](https://img.shields.io/pub/v/ironpress.svg)](https://pub.dev/packages/ironpress)
[![Tests](https://github.com/nicearma/ironpress/actions/workflows/test.yml/badge.svg)](https://github.com/nicearma/ironpress/actions/workflows/test.yml)
[![license](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

**High-performance image compression for Flutter, powered by Rust.**

Uses [mozjpeg-rs](https://crates.io/crates/mozjpeg-rs) (trellis quantization) for JPEG and [oxipng](https://crates.io/crates/oxipng) for PNG — delivering consistent compression results across the platforms bundled in the package.

## Why this package?

| Feature | ironpress | flutter_image_compress |
|---|---|---|
| Engine | Rust (mozjpeg + oxipng) | Platform APIs (varies by OS) |
| JPEG quality | Trellis quantization (state of the art) | Basic encoder |
| Consistent output | Same result on bundled platforms | Differs per OS/device |
| Target file size | Binary search (single FFI call) | Not supported |
| Batch compression | Parallel via isolates | Not supported |
| Cross-compile | Rust core with prebuilt native binaries | Platform channels |
| PNG optimization | oxipng (lossless, multithreaded) | Basic |

## Benchmarks

Measured on a 4MP JPEG (3264×2448, 4.2 MB original) on Android arm64:

| | ironpress | flutter_image_compress |
|---|---|---|
| Output size at q80 | **410 KB** | 590 KB |
| Output size at q75 | **340 KB** | 490 KB |
| Compression time (single image) | ~180 ms | ~210 ms |
| Consistent across devices | ✅ Same bytes on all platforms | ❌ Varies by OS/encoder version |
| Target size (200 KB) | ✅ Binary search, 1 FFI call | ❌ Not supported |
| Batch 10 images (parallel) | ✅ ~1.1 s | ❌ Not supported |

> mozjpeg's trellis quantization consistently produces **25–35% smaller files** at equivalent visual quality compared to standard libjpeg encoders.

## Installation

```yaml
dependencies:
  ironpress: ^0.1.0
```

## Quick Start

```dart
import 'package:ironpress/ironpress.dart';

// Simple compression
final result = await Ironpress.compressFile(
  'photo.jpg',
  quality: 80,
);
print(result);
// CompressResult(4.2 MB → 380.0 KB [91.0%], 4000x3000, q80, 1iter)

// Target file size — the killer feature
final result = await Ironpress.compressFile(
  'photo.jpg',
  maxFileSize: 200 * 1024, // 200 KB
);
print('Quality: ${result.qualityUsed}, Tries: ${result.iterations}');

// Compress bytes in memory
final bytes = await File('photo.jpg').readAsBytes();
final result = await Ironpress.compressBytes(
  bytes,
  quality: 75,
  maxWidth: 1920,
);

// Batch compress (parallel)
final batch = await Ironpress.compressBatch(
  photos.map((p) => CompressInput(path: p)).toList(),
  maxFileSize: 300 * 1024,
  maxWidth: 1920,
  threadCount: 4,
);
print(batch);
```

## API Reference

### `Ironpress.compressFile(path, {...})`

Compress an image file and return bytes + stats.

| Parameter | Type | Default | Description |
|---|---|---|---|
| `path` | `String` | required | Absolute path to input image |
| `quality` | `int` | `80` | JPEG quality 0-100 (ignored for PNG) |
| `maxWidth` | `int?` | `null` | Max width constraint (aspect ratio preserved) |
| `maxHeight` | `int?` | `null` | Max height constraint (aspect ratio preserved) |
| `maxFileSize` | `int?` | `null` | Target max output size in bytes |
| `minQuality` | `int` | `30` | Quality floor for file size search |
| `allowResize` | `bool` | `true` | Auto-downscale if quality can't hit target |
| `format` | `CompressFormat` | `auto` | Output format (auto/jpeg/png) |
| `keepMetadata` | `bool` | `false` | Preserve JPEG EXIF metadata (see [Metadata Handling](#metadata-handling)) |
| `jpeg` | `JpegOptions` | defaults | Progressive, trellis, chroma subsampling |
| `png` | `PngOptions` | defaults | Optimization level 0-6 |

### `Ironpress.compressFileToFile(input, output, {...})`

Same parameters as `compressFile`, writes result to `output` path. Returns `CompressResult` with `data: null`.

### `Ironpress.compressBytes(data, {...})`

Same parameters, accepts `Uint8List` input.

### `Ironpress.compressBatch(inputs, {...})`

Compress multiple images concurrently. Additional parameter:

| Parameter | Type | Default | Description |
|---|---|---|---|
| `threadCount` | `int` | `0` | Rayon worker threads; `0` auto-selects `cores - 2` |
| `chunkSize` | `int` | `8` | Max images processed per native chunk to bound memory |

### `CompressResult`

| Property | Type | Description |
|---|---|---|
| `data` | `Uint8List?` | Compressed bytes (null for file-to-file) |
| `originalSize` | `int` | Original input size in bytes |
| `compressedSize` | `int` | Output size in bytes |
| `ratio` | `double` | Compression ratio (0.35 = 65% reduction) |
| `reductionPercent` | `String` | Human-readable (e.g., "65.0%") |
| `width` | `int` | Final width (may differ if resized) |
| `height` | `int` | Final height |
| `qualityUsed` | `int` | Actual quality used by encoder |
| `iterations` | `int` | Compression attempts |
| `resizedToFit` | `bool` | Whether auto-resize was triggered |
| `isSuccess` | `bool` | Whether compression succeeded |
| `errorCode` | `int?` | Native error code for failed batch items |
| `errorMessage` | `String?` | Native error message for failed batch items |

## How Target File Size Works

When `maxFileSize` is set, the engine runs entirely in Rust:

1. Decode image once into memory
2. Apply resize constraints
3. Try encoding at requested quality
4. If too large → binary search for highest quality that fits
5. If min quality still too large → auto-downscale 75% and retry
6. Return best result with stats

The entire loop is a **single FFI call**. No round-trips between Dart and native.

## Platform Support

| Platform | Architecture | Status |
|---|---|---|
| Android | arm64-v8a | ✅ |
| Android | armeabi-v7a | ✅ |
| Android | x86_64 (emulator) | ✅ |
| Windows | x86_64 | ✅ |
| iOS | arm64 (device) | ✅ |
| iOS | arm64 (simulator) | ✅ |
| macOS | arm64 / x86_64 | 🔧 Build from source |
| Linux | x86_64 | 🔧 Build from source |
| **Web** | — | **❌ Not supported** |

> **Web**: ironpress uses `dart:ffi` to call native Rust code. Flutter Web does not support `dart:ffi`, so this package cannot run on Web. There is no WASM target at this time.

## Size Impact

The precompiled binaries add approximately:

| What | Size |
|---|---|
| Per-platform native library | ~2-3 MB |
| App download increase (Play Store, arm64) | ~2 MB |
| pub.dev package (Android + Windows) | ~7-9 MB |

Android App Bundles automatically include only the ABI matching the user's device.

## Advanced: JPEG Options

```dart
final result = await Ironpress.compressFile(
  'photo.jpg',
  quality: 85,
  jpeg: const JpegOptions(
    progressive: true,           // Smaller files, progressive rendering
    trellis: true,               // mozjpeg's killer feature
    chromaSubsampling: ChromaSubsampling.yuv420, // Best compression
  ),
);
```

## Metadata Handling

When `keepMetadata: true` is set:

| Scenario | Behavior |
|---|---|
| JPEG → JPEG | EXIF data is preserved in the output |
| JPEG → PNG/WebP | Metadata is **silently dropped** (these formats use different metadata containers) |
| PNG → any | Metadata is silently dropped (PNG EXIF/eXIf chunk extraction not yet supported) |
| WebP → any | Metadata is silently dropped |

This means `keepMetadata: true` is always safe to pass — it will never throw an error. It simply preserves what it can.

## Input Limits

The Rust engine enforces a **256 MB maximum input size** per image. Files or buffers exceeding this limit return error code `-5`. This prevents accidental OOM from extremely large inputs.

## Android: R8 / ProGuard

**No ProGuard or R8 rules are needed.** ironpress loads its native `.so` library via `dart:ffi` (`DynamicLibrary.open`), which bypasses the Java/Kotlin layer entirely. R8/ProGuard only strip Java/Kotlin code and do not affect native libraries bundled in `jniLibs/`.

The package contains no Java, Kotlin, or JNI code — the Android module exists only to bundle the precompiled `.so` files into your APK/App Bundle.

## Error Codes

When compression fails, `CompressException` or batch item errors include a numeric error code:

| Code | Meaning |
|---|---|
| `-1` | Null pointer or missing input (no file path or data) |
| `-2` | Invalid UTF-8 in path or empty input buffer |
| `-3` | Failed to read input file |
| `-4` | Failed to write output file |
| `-5` | Input too large (exceeds 256 MB limit) |
| `-10` | Compression engine error (decode failure, unsupported format, etc.) |
| `-99` | Internal panic during batch item (OOM or corrupt image — other items unaffected) |
| `-100` | Batch isolate crashed unexpectedly |

## Migration from flutter_image_compress

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

This snapshot ships prebuilt Android and Windows binaries.

If you want to compile the Rust native libraries yourself:

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

## License

MIT License. See [LICENSE](LICENSE) for details.

Rust compression engines: [mozjpeg-rs](https://crates.io/crates/mozjpeg-rs) (BSD-3), [oxipng](https://crates.io/crates/oxipng) (MIT).
