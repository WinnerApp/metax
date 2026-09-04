import 'dart:async';

import 'package:meta_tool/estimated_progress.dart';
import 'package:test/test.dart';

void main() {
  group('extractEstimatedSeconds', () {
    test('returns null when option absent', () {
      final result = extractEstimatedSeconds(['build', 'framework', 'flutter']);
      expect(result.estimatedSeconds, isNull);
      expect(result.args, ['build', 'framework', 'flutter']);
    });

    test('extracts from anywhere with --estimatedSeconds', () {
      final result = extractEstimatedSeconds([
        'build',
        'framework',
        'flutter',
        '--estimatedSeconds',
        '600',
        '--branch',
        'main',
      ]);
      expect(result.estimatedSeconds, 600);
      expect(result.args, [
        'build',
        'framework',
        'flutter',
        '--branch',
        'main',
      ]);
    });

    test('supports --seconds alias and equals form', () {
      expect(
        extractEstimatedSeconds(['--seconds=90', 'build']).estimatedSeconds,
        90,
      );
      expect(
        extractEstimatedSeconds(['build', '--estimatedSeconds=120'])
            .estimatedSeconds,
        120,
      );
    });

    test('rejects non-positive values', () {
      expect(
        () => extractEstimatedSeconds(['--seconds', '0']),
        throwsFormatException,
      );
      expect(
        () => extractEstimatedSeconds(['--estimatedSeconds', 'abc']),
        throwsFormatException,
      );
    });
  });

  group('describeMetaxCommand', () {
    test('skips leading global options and trailing flags', () {
      expect(
        describeMetaxCommand([
          '--workspace',
          '/tmp/app',
          'build',
          'framework',
          'flutter',
          '--branch',
          'main',
        ]),
        'build framework flutter',
      );
    });
  });

  group('formatElapsedDuration', () {
    test('formats seconds minutes and hours', () {
      expect(formatElapsedDuration(const Duration(seconds: 45)), '45s');
      expect(formatElapsedDuration(const Duration(seconds: 192)), '3m 12s');
      expect(
        formatElapsedDuration(const Duration(seconds: 3723)),
        '1h 2m 3s',
      );
    });
  });

  group('estimatedProgressPercent', () {
    test('scales with elapsed time and clamps at 100', () {
      expect(
        estimatedProgressPercent(elapsedSeconds: 0, estimatedSeconds: 100),
        0,
      );
      expect(
        estimatedProgressPercent(elapsedSeconds: 50, estimatedSeconds: 100),
        50,
      );
      expect(
        estimatedProgressPercent(elapsedSeconds: 150, estimatedSeconds: 100),
        100,
      );
    });
  });

  group('renderEstimatedProgressBar', () {
    test('includes percent and time', () {
      final line = renderEstimatedProgressBar(
        percent: 50,
        elapsedSeconds: 150,
        estimatedSeconds: 300,
        width: 10,
      );
      expect(line, contains('50%'));
      expect(line, contains('150s / 300s'));
      expect(line, contains('█'));
      expect(line, contains('░'));
    });
  });

  group('EstimatedProgress', () {
    test('stops updating after reaching 100%', () async {
      final logs = <String>[];
      final progress = EstimatedProgress(
        estimatedSeconds: 1,
        tickInterval: const Duration(milliseconds: 50),
        isTerminal: false,
        logInfo: logs.add,
      );

      progress.start();
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      final countAtCap = logs.length;
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(logs.length, countAtCap);
      expect(logs.last, contains('100%'));
      progress.stop();
    });

    test('complete jumps to 100%', () {
      final logs = <String>[];
      final progress = EstimatedProgress(
        estimatedSeconds: 1000,
        tickInterval: const Duration(hours: 1),
        isTerminal: false,
        logInfo: logs.add,
      );

      progress.start();
      progress.complete();
      expect(logs.last, contains('100%'));
    });
  });
}
