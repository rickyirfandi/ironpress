import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ironpress/ironpress.dart';

void main() {
  group('Input validation', () {
    test('compressFile throws on empty path', () async {
      expect(() => Ironpress.compressFile(''), throwsA(isA<ArgumentError>()));
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

    test('probeFile throws on empty path', () async {
      expect(() => Ironpress.probeFile(''), throwsA(isA<ArgumentError>()));
    });

    test('probeBytes throws on empty data', () async {
      expect(
        () => Ironpress.probeBytes(Uint8List(0)),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('benchmarkFile throws on empty path', () async {
      expect(() => Ironpress.benchmarkFile(''), throwsA(isA<ArgumentError>()));
    });

    test('benchmarkBytes throws on empty data', () async {
      expect(
        () => Ironpress.benchmarkBytes(Uint8List(0)),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('Quality range validation', () {
    test('compressFile throws on quality > 100', () {
      expect(
        () => Ironpress.compressFile('/photo.jpg', quality: 101),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('compressFile throws on quality < 0', () {
      expect(
        () => Ironpress.compressFile('/photo.jpg', quality: -1),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('compressBytes throws on quality > 100', () {
      expect(
        () => Ironpress.compressBytes(Uint8List(1), quality: 150),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('compressFile throws on minQuality > 100', () {
      expect(
        () => Ironpress.compressFile('/photo.jpg', minQuality: 101),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('compressBatch throws on out-of-range quality', () {
      expect(
        () => Ironpress.compressBatch([
          CompressInput(data: Uint8List(1)),
        ], quality: 200),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('compressFile accepts boundary values 0 and 100', () {
      // Should not throw ArgumentError — just needs to pass validation.
      // (Will fail later when native lib tries to load, which is fine here.)
      expect(
        () => Ironpress.compressFile('/photo.jpg', quality: 0),
        isNot(throwsA(isA<ArgumentError>())),
      );
      expect(
        () => Ironpress.compressFile('/photo.jpg', quality: 100),
        isNot(throwsA(isA<ArgumentError>())),
      );
    });
  });

  group('CompressException', () {
    test('creation and toString includes code and message', () {
      const ex = CompressException(-3, 'File not found');
      expect(ex.code, -3);
      expect(ex.message, 'File not found');
      expect(ex.toString(), contains('-3'));
      expect(ex.toString(), contains('File not found'));
    });

    test('hint is non-empty for known error codes', () {
      const codes = [-1, -2, -3, -4, -5, -10, -99, -100];
      for (final code in codes) {
        final ex = CompressException(code, 'msg');
        expect(ex.hint, isNotEmpty, reason: 'code $code should have a hint');
      }
    });

    test('hint is empty for unknown error codes', () {
      const ex = CompressException(-999, 'msg');
      expect(ex.hint, isEmpty);
    });

    test('toString includes hint when known code', () {
      const ex = CompressException(-3, 'File not found');
      expect(ex.toString(), contains('Hint:'));
    });

    test('toString does not include hint for unknown code', () {
      const ex = CompressException(-999, 'msg');
      expect(ex.toString(), isNot(contains('Hint:')));
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
