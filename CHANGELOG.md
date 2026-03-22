## 0.1.1

### Bug fixes
- Fixed resource leak in `compressBatch` with progress callbacks: `ReceivePort`s were
  not closed if `Isolate.spawn()` raised an exception. Ports are now always closed in a
  `finally` block.

### API improvements
- Renamed `Ironpress.probe(path)` → `Ironpress.probeFile(path)` to be consistent with
  `probeBytes`. The old name is kept as a `@Deprecated` alias.
- Renamed `Ironpress.benchmark(path)` → `Ironpress.benchmarkFile(path)` for the same
  reason. The old name is kept as a `@Deprecated` alias.
- `compressFile`, `compressFileToFile`, `compressBytes`, and `compressBatch` now throw
  `ArgumentError` immediately when `quality` or `minQuality` is outside 0–100, instead
  of silently clamping to the nearest boundary.
- `JpegOptions`, `PngOptions`, and `CompressPreset` are now annotated `@immutable`,
  which lets the analyzer warn if a mutable field is accidentally introduced.

---

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
- `Ironpress.probe` / `Ironpress.probeBytes` — read image dimensions and format without decoding pixels
- `Ironpress.benchmark` / `Ironpress.benchmarkBytes` — sweep quality levels to generate a compression/size curve
- `Ironpress.nativeVersion` — verify the loaded native library version

### Key features
- **Binary-search target file size** (`maxFileSize`): the engine loops entirely in Rust — single FFI call, no round-trips
- **Auto-resize fallback**: if quality alone can't reach `maxFileSize`, image is downscaled and retried
- **Aspect-ratio-preserving resize** via `maxWidth` / `maxHeight`
- **Batch panic safety**: one corrupt image never crashes the batch; other items continue normally
- **ABI version checking**: prevents stale native library mismatches from causing silent bugs
- **EXIF metadata preservation** for JPEG→JPEG (`keepMetadata: true`)
- **Format conversion**: auto-detect input, choose output format (JPEG / PNG / WebP lossy / WebP lossless)

### Platform support
- Android: `arm64-v8a`, `armeabi-v7a`, `x86_64` (precompiled `.so`)
- iOS: device + simulator (precompiled `xcframework`)
- Windows: `x86_64` (precompiled `.dll`)
- Linux: `x86_64` (build from source — see README)
- macOS: `arm64` + `x86_64` universal (build from source — see README)
- Web: not supported (`dart:ffi` is unavailable on Flutter Web)
