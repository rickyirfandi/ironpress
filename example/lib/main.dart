import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ironpress/ironpress.dart';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ironpress Example',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.blue,
      ),
      home: const CompressDemo(),
    );
  }
}

class CompressDemo extends StatefulWidget {
  const CompressDemo({super.key});

  @override
  State<CompressDemo> createState() => _CompressDemoState();
}

class _CompressDemoState extends State<CompressDemo> {
  String _log = 'Tap a button to compress an image.\n';
  bool _loading = false;

  void _appendLog(String msg) {
    setState(() => _log += '$msg\n');
  }

  /// Load a test image. Tries common paths, falls back to generating a
  /// synthetic JPEG so the demo works on any platform without setup.
  Future<Uint8List> _loadTestImage() async {
    // Try platform-specific paths
    final candidates = <String>[
      if (Platform.isAndroid) '/sdcard/DCIM/Camera/photo.jpg',
      if (Platform.isWindows) '${Platform.environment['USERPROFILE']}\\Pictures\\test.jpg',
      if (Platform.isLinux) '${Platform.environment['HOME']}/Pictures/test.jpg',
      if (Platform.isMacOS) '${Platform.environment['HOME']}/Pictures/test.jpg',
    ];

    for (final path in candidates) {
      final file = File(path);
      if (file.existsSync()) {
        _appendLog('Using image: $path');
        return file.readAsBytesSync();
      }
    }

    // Try bundled asset
    try {
      final data = await rootBundle.load('assets/test.jpg');
      _appendLog('Using bundled asset');
      return data.buffer.asUint8List();
    } catch (_) {
      // No asset available
    }

    // Generate a synthetic test image (minimal JPEG)
    _appendLog('No test image found — using synthetic image');
    _appendLog('Place a JPEG at one of: ${candidates.join(', ')}');
    return _syntheticJpeg();
  }

  /// Minimal valid JPEG (1x1 white pixel) for testing without external files.
  Uint8List _syntheticJpeg() {
    return Uint8List.fromList([
      0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00,
      0x01, 0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0xFF, 0xDB,
      0x00, 0x43, 0x00, 0x08, 0x06, 0x06, 0x07, 0x06, 0x05, 0x08, 0x07,
      0x07, 0x07, 0x09, 0x09, 0x08, 0x0A, 0x0C, 0x14, 0x0D, 0x0C, 0x0B,
      0x0B, 0x0C, 0x19, 0x12, 0x13, 0x0F, 0x14, 0x1D, 0x1A, 0x1F, 0x1E,
      0x1D, 0x1A, 0x1C, 0x1C, 0x20, 0x24, 0x2E, 0x27, 0x20, 0x22, 0x2C,
      0x23, 0x1C, 0x1C, 0x28, 0x37, 0x29, 0x2C, 0x30, 0x31, 0x34, 0x34,
      0x34, 0x1F, 0x27, 0x39, 0x3D, 0x38, 0x32, 0x3C, 0x2E, 0x33, 0x34,
      0x32, 0xFF, 0xC0, 0x00, 0x0B, 0x08, 0x00, 0x01, 0x00, 0x01, 0x01,
      0x01, 0x11, 0x00, 0xFF, 0xC4, 0x00, 0x1F, 0x00, 0x00, 0x01, 0x05,
      0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00,
      0x00, 0x00, 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
      0x09, 0x0A, 0x0B, 0xFF, 0xC4, 0x00, 0xB5, 0x10, 0x00, 0x02, 0x01,
      0x03, 0x03, 0x02, 0x04, 0x03, 0x05, 0x05, 0x04, 0x04, 0x00, 0x00,
      0x01, 0x7D, 0x01, 0x02, 0x03, 0x00, 0x04, 0x11, 0x05, 0x12, 0x21,
      0x31, 0x41, 0x06, 0x13, 0x51, 0x61, 0x07, 0x22, 0x71, 0x14, 0x32,
      0x81, 0x91, 0xA1, 0x08, 0x23, 0x42, 0xB1, 0xC1, 0x15, 0x52, 0xD1,
      0xF0, 0x24, 0x33, 0x62, 0x72, 0x82, 0x09, 0x0A, 0x16, 0x17, 0x18,
      0x19, 0x1A, 0x25, 0x26, 0x27, 0x28, 0x29, 0x2A, 0x34, 0x35, 0x36,
      0x37, 0x38, 0x39, 0x3A, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49,
      0x4A, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5A, 0x63, 0x64,
      0x65, 0x66, 0x67, 0x68, 0x69, 0x6A, 0x73, 0x74, 0x75, 0x76, 0x77,
      0x78, 0x79, 0x7A, 0x83, 0x84, 0x85, 0x86, 0x87, 0x88, 0x89, 0x8A,
      0x92, 0x93, 0x94, 0x95, 0x96, 0x97, 0x98, 0x99, 0x9A, 0xA2, 0xA3,
      0xA4, 0xA5, 0xA6, 0xA7, 0xA8, 0xA9, 0xAA, 0xB2, 0xB3, 0xB4, 0xB5,
      0xB6, 0xB7, 0xB8, 0xB9, 0xBA, 0xC2, 0xC3, 0xC4, 0xC5, 0xC6, 0xC7,
      0xC8, 0xC9, 0xCA, 0xD2, 0xD3, 0xD4, 0xD5, 0xD6, 0xD7, 0xD8, 0xD9,
      0xDA, 0xE1, 0xE2, 0xE3, 0xE4, 0xE5, 0xE6, 0xE7, 0xE8, 0xE9, 0xEA,
      0xF1, 0xF2, 0xF3, 0xF4, 0xF5, 0xF6, 0xF7, 0xF8, 0xF9, 0xFA, 0xFF,
      0xDA, 0x00, 0x08, 0x01, 0x01, 0x00, 0x00, 0x3F, 0x00, 0x7B, 0x94,
      0x11, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF, 0xD9,
    ]);
  }

  // ─── Example 1: Simple compression ──────────────────────────────────

  Future<void> _simpleCompress() async {
    setState(() => _loading = true);
    try {
      final bytes = await _loadTestImage();
      final result = await Ironpress.compressBytes(bytes, quality: 80);
      _appendLog('Simple: $result');
    } catch (e) {
      _appendLog('Error: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  // ─── Example 2: Target file size ──────────────────────────────────

  Future<void> _targetSizeCompress() async {
    setState(() => _loading = true);
    try {
      final bytes = await _loadTestImage();
      final result = await Ironpress.compressBytes(
        bytes,
        maxFileSize: 200 * 1024,
        maxWidth: 1920,
      );

      _appendLog('Target 200KB: $result');
      _appendLog('  Quality chosen: ${result.qualityUsed}');
      _appendLog('  Iterations: ${result.iterations}');
      _appendLog('  Auto-resized: ${result.resizedToFit}');
    } catch (e) {
      _appendLog('Error: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  // ─── Example 3: Batch compression ──────────────────────────────────

  Future<void> _batchCompress() async {
    setState(() => _loading = true);
    try {
      final bytes = await _loadTestImage();
      final inputs = List.generate(
        5,
        (_) => CompressInput(data: bytes),
      );

      final batch = await Ironpress.compressBatch(
        inputs,
        quality: 80,
        maxFileSize: 300 * 1024,
        maxWidth: 1920,
        onProgress: (done, total) {
          // Safe to call setState from main thread
        },
      );

      _appendLog('Batch: $batch');
      for (var i = 0; i < batch.results.length; i++) {
        _appendLog('  [$i] ${batch.results[i]}');
      }
    } catch (e) {
      _appendLog('Error: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  // ─── Example 4: Version check ──────────────────────────────────────

  void _checkVersion() {
    try {
      final version = Ironpress.nativeVersion;
      _appendLog('Native library version: $version');
    } catch (e) {
      _appendLog('Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ironpress')),
      body: Column(
        children: [
          if (_loading) const LinearProgressIndicator(),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton(
                  onPressed: _loading ? null : _simpleCompress,
                  child: const Text('Simple'),
                ),
                ElevatedButton(
                  onPressed: _loading ? null : _targetSizeCompress,
                  child: const Text('Target 200KB'),
                ),
                ElevatedButton(
                  onPressed: _loading ? null : _batchCompress,
                  child: const Text('Batch x5'),
                ),
                OutlinedButton(
                  onPressed: _checkVersion,
                  child: const Text('Version'),
                ),
                TextButton(
                  onPressed: () => setState(() => _log = ''),
                  child: const Text('Clear'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: SelectableText(
                _log,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
