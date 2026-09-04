import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:meta_tool/common.dart';

/// 从参数里取出命令路径（跳过前置全局选项），例如 `build framework flutter`。
String describeMetaxCommand(List<String> args) {
  final parts = <String>[];
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg.startsWith('-')) {
      if (parts.isNotEmpty) break;
      final hasInlineValue = arg.contains('=');
      final isNegatedFlag = arg.startsWith('--no-');
      if (!hasInlineValue &&
          !isNegatedFlag &&
          i + 1 < args.length &&
          !args[i + 1].startsWith('-')) {
        i++;
      }
      continue;
    }
    parts.add(arg);
  }
  return parts.isEmpty ? 'metax' : parts.join(' ');
}

/// 将耗时格式化为可读字符串，例如 `45s`、`3m 12s`、`1h 2m 3s`。
String formatElapsedDuration(Duration elapsed) {
  final totalSeconds = elapsed.inSeconds;
  if (totalSeconds < 60) {
    return '${totalSeconds}s';
  }
  final hours = elapsed.inHours;
  final minutes = elapsed.inMinutes.remainder(60);
  final seconds = totalSeconds.remainder(60);
  if (hours > 0) {
    return '${hours}h ${minutes}m ${seconds}s';
  }
  return '${minutes}m ${seconds}s';
}

/// 从命令行参数中提取 `--estimatedSeconds` / `--seconds`，可出现在任意位置。
({List<String> args, int? estimatedSeconds}) extractEstimatedSeconds(
  List<String> arguments,
) {
  final out = <String>[];
  int? estimatedSeconds;

  for (var i = 0; i < arguments.length; i++) {
    final arg = arguments[i];
    if (arg == '--estimatedSeconds' || arg == '--seconds') {
      if (i + 1 >= arguments.length) {
        throw FormatException('缺少 $arg 的值（正整数秒）');
      }
      estimatedSeconds = _parsePositiveSeconds(arguments[++i], arg);
    } else if (arg.startsWith('--estimatedSeconds=') ||
        arg.startsWith('--seconds=')) {
      final name = arg.substring(0, arg.indexOf('='));
      final raw = arg.substring(arg.indexOf('=') + 1);
      estimatedSeconds = _parsePositiveSeconds(raw, name);
    } else {
      out.add(arg);
    }
  }

  return (args: out, estimatedSeconds: estimatedSeconds);
}

int _parsePositiveSeconds(String raw, String optionName) {
  final value = int.tryParse(raw.trim());
  if (value == null || value <= 0) {
    throw FormatException('$optionName 必须是正整数秒，收到: $raw');
  }
  return value;
}

/// 按预估总秒数推算进度百分比，上限 100。
int estimatedProgressPercent({
  required double elapsedSeconds,
  required int estimatedSeconds,
}) {
  if (estimatedSeconds <= 0) return 100;
  final pct = (elapsedSeconds / estimatedSeconds * 100).floor();
  return math.min(100, math.max(0, pct));
}

String renderEstimatedProgressBar({
  required int percent,
  required double elapsedSeconds,
  required int estimatedSeconds,
  int width = 28,
}) {
  final clamped = percent.clamp(0, 100);
  final filled = (width * clamped / 100).round().clamp(0, width);
  final bar = '${'█' * filled}${'░' * (width - filled)}';
  final elapsed = elapsedSeconds.floor();
  return '[估算进度] [$bar] $clamped% · ${elapsed}s / ${estimatedSeconds}s';
}

/// 按预估耗时在终端显示估算进度条；达到 100% 后停止更新。
class EstimatedProgress {
  EstimatedProgress({
    required this.estimatedSeconds,
    Duration tickInterval = const Duration(milliseconds: 500),
    IOSink? sink,
    bool? isTerminal,
    void Function(String message)? logInfo,
  })  : _tickInterval = tickInterval,
        _sink = sink ?? stderr,
        _isTerminal = isTerminal ?? stderr.hasTerminal,
        _logInfo = logInfo ?? loggerInfo;

  final int estimatedSeconds;
  final Duration _tickInterval;
  final IOSink _sink;
  final bool _isTerminal;
  final void Function(String message) _logInfo;

  final Stopwatch _stopwatch = Stopwatch();
  Timer? _timer;
  int _lastPrintedPct = -1;
  bool _stopped = false;
  bool _wroteInline = false;

  Duration get elapsed => _stopwatch.elapsed;

  void start() {
    if (_stopped) return;
    _logInfo('已启用估算进度条，预估耗时 ${estimatedSeconds}s');
    _stopwatch.start();
    _timer = Timer.periodic(_tickInterval, (_) => _tick());
    _tick();
  }

  /// 命令正常结束：若未到 100% 则补到 100% 并停止。
  void complete() {
    if (_stopped) return;
    _render(100, _stopwatch.elapsedMilliseconds / 1000.0, force: true);
    stop();
  }

  /// 命令异常结束：保留当前进度并停止。
  void stop() {
    if (_stopped) return;
    _stopped = true;
    _timer?.cancel();
    _timer = null;
    _stopwatch.stop();
    if (_wroteInline) {
      _sink.writeln();
      _wroteInline = false;
    }
  }

  void _tick() {
    if (_stopped) return;
    final elapsed = _stopwatch.elapsedMilliseconds / 1000.0;
    final pct = estimatedProgressPercent(
      elapsedSeconds: elapsed,
      estimatedSeconds: estimatedSeconds,
    );
    _render(pct, elapsed);
    if (pct >= 100) {
      // 达到预估上限后停止更新，命令本身可继续跑。
      _timer?.cancel();
      _timer = null;
    }
  }

  void _render(int pct, double elapsed, {bool force = false}) {
    if (!force && pct == _lastPrintedPct) return;

    // 非 TTY（如 Jenkins 日志）每 5% 打一行，避免刷屏；TTY 用 \r 原地刷新。
    if (!_isTerminal && !force && pct < 100 && pct % 5 != 0) {
      return;
    }

    _lastPrintedPct = pct;
    final line = renderEstimatedProgressBar(
      percent: pct,
      elapsedSeconds: elapsed,
      estimatedSeconds: estimatedSeconds,
    );

    if (_isTerminal) {
      _sink.write('\r$line');
      _wroteInline = true;
    } else {
      if (_wroteInline) {
        _sink.writeln();
        _wroteInline = false;
      }
      _logInfo(line);
    }
  }
}
