import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ironpress/ironpress.dart';

void main() {
  group('Input validation', () {
    test('compressFile throws on empty path', () async {
      expect(
        () => Ironpress.compressFile(''),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('compressFileToFile throws on empty inputPath', () async {
      expect(
        () => Ironpress.compressFileToFile('', '/out.jpg'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('compressFileToFile throws on empty outputPath', () async {
      expect(
        () => Ironpress.compressFileToFile('/in.jpg', ''),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('compressBytes throws on empty data', () async {
      expect(
        () => Ironpress.compressBytes(Uint8List(0)),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('probe throws on empty path', () async {
      expect(
        () => Ironpress.probe(''),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('probeBytes throws on empty data', () async {
      expect(
        () => Ironpress.probeBytes(Uint8List(0)),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('benchmark throws on empty path', () async {
      expect(
        () => Ironpress.benchmark(''),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('benchmarkBytes throws on empty data', () async {
      expect(
        () => Ironpress.benchmarkBytes(Uint8List(0)),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('CompressException', () {
    test('creation and toString', () {
      const ex = CompressException(-3, 'File not found');
      expect(ex.code, -3);
      expect(ex.message, 'File not found');
      expect(ex.toString(), contains('-3'));
      expect(ex.toString(), contains('File not found'));
    });
  });

  group('Batch empty input', () {
    test('compressBatch returns empty result for empty list', () async {
      final result = await Ironpress.compressBatch([]);
      expect(result.results, isEmpty);
      expect(result.elapsedMs, 0);
    });
  });
}
