## 0.1.0

- Initial release
- JPEG compression via mozjpeg-rs (pure Rust, trellis quantization)
- PNG optimization via oxipng (pure Rust, multithreaded)
- Binary-search target file size (`maxFileSize`)
- Auto-resize fallback when quality alone can't hit target
- Batch compression with configurable concurrency
- Resize with aspect ratio preservation
- Format auto-detection and conversion (JPEG ↔ PNG)
- Android (arm64, armv7, x86_64) and iOS (device + simulator) support
- Full `CompressResult` with stats (ratio, quality used, iterations)
