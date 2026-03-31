import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'perf_benchmark.dart' as perf;

void main() {
  test('manual performance benchmark', () async {
    final previousExitCode = exitCode;
    exitCode = 0;
    try {
      await perf.main(_argsFromEnvironment());
      expect(exitCode, 0);
    } finally {
      exitCode = previousExitCode;
    }
  }, timeout: Timeout.none);
}

List<String> _argsFromEnvironment() {
  final args = <String>[];

  void add(String envName, String flagName) {
    final value = Platform.environment[envName];
    if (value != null && value.isNotEmpty) {
      args.add('--$flagName=$value');
    }
  }

  add('IRONPRESS_BENCH_WARMUP', 'warmup');
  add('IRONPRESS_BENCH_RUNS', 'runs');
  add('IRONPRESS_BENCH_BATCH_SIZE', 'batch-size');
  add('IRONPRESS_BENCH_CHUNK_SIZE', 'chunk-size');
  add('IRONPRESS_BENCH_THREAD_COUNT', 'thread-count');
  add('IRONPRESS_BENCH_QUALITY', 'quality');
  add('IRONPRESS_BENCH_CORPUS_DIR', 'corpus-dir');

  return args;
}
