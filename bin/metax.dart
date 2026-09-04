import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:meta_tool/app_home_dir.dart';
import 'package:meta_tool/commands/build/build_command.dart';
import 'package:meta_tool/commands/cache/cache_command.dart';
import 'package:meta_tool/commands/first_package/first_package_command.dart';
import 'package:meta_tool/commands/flutter/flutter_command.dart';
import 'package:meta_tool/commands/init/init.dart';
import 'package:meta_tool/commands/patch/patch_command.dart';
import 'package:meta_tool/commands/publish/publish_command.dart';
import 'package:meta_tool/commands/test/test_command.dart';
import 'package:meta_tool/commands/upload/upload_command.dart';
import 'package:meta_tool/common.dart';
import 'package:meta_tool/define.dart';
import 'package:meta_tool/estimated_progress.dart';

Future<void> main(List<String> arguments) async {
  // 在 Windows 下显式使用 UTF-8，减少中文乱码和输入异常
  if (Platform.isWindows) {
    stdout.encoding = utf8;
    stderr.encoding = utf8;
  }

  late final List<String> commandArgs;
  late final int? estimatedSeconds;
  try {
    final extracted = extractEstimatedSeconds(arguments);
    commandArgs = extracted.args;
    estimatedSeconds = extracted.estimatedSeconds;
  } on FormatException catch (e) {
    stderr.writeln(e.message);
    exitCode = 64;
    return;
  }

  final runner = CommandRunner('metax', '一款棉宇宙开发和发布工具（v0.3.5）')
    ..addCommand(InitCommand())
    ..addCommand(BuildCommand())
    ..addCommand(UploadCommand())
    ..addCommand(PatchCommand())
    ..addCommand(CacheCommand())
    ..addCommand(FlutterCommand())
    ..addCommand(PublishCommand())
    ..addCommand(TestCommand())
    ..addCommand(FirstPackageCommand());
  runner.argParser.addOption(
    'estimatedSeconds',
    help: '预估本次命令总耗时（秒）。按时间显示估算进度条，达到 100% 后停止更新；'
        '也可写作 --seconds。可放在命令任意位置。',
  );
  runner.argParser.addOption(
    'workspace',
    help: 'app运行目录，默认使用当前目录',
    defaultsTo: Directory.current.path,
    callback: (value) {
      appHomeDir = AppHomeDir(value!);
    },
  );
  runner.argParser.addFlag(
    'isUseMock',
    help: '是否使用mock数据，默认不使用',
    defaultsTo: false,
    callback: (value) {
      useMock = value;
    },
  );
  runner.argParser.addOption(
    'unityPath',
    help: '自定义当前环境的Unity版本路径',
    callback: (p0) {
      customUnityPath = p0;
    },
  );
  runner.argParser.addFlag(
    'isUseCache',
    help: '是否使用缓存（全局开关，关闭后 Flutter/Unity 均不使用缓存）',
    defaultsTo: true,
    callback: (value) {
      isUseCache = value;
    },
  );
  runner.argParser.addFlag(
    'isUseFlutterCache',
    help: '是否使用 Flutter 缓存（需同时开启 --isUseCache）',
    defaultsTo: true,
    callback: (value) {
      isUseFlutterCache = value;
    },
  );
  runner.argParser.addFlag(
    'isUseUnityCache',
    help: '是否使用 Unity 缓存（需同时开启 --isUseCache）',
    defaultsTo: true,
    callback: (value) {
      isUseUnityCache = value;
    },
  );
  runner.argParser.addFlag(
    'skipGitPull',
    help: '跳过拉取最新代码，使用本地提交',
    defaultsTo: false,
    callback: (value) {
      skipGitPull = value;
    },
  );

  EstimatedProgress? progress;
  final isHelpOnly = commandArgs.isEmpty ||
      commandArgs.contains('--help') ||
      commandArgs.contains('-h') ||
      commandArgs.first == 'help';
  final commandStopwatch = Stopwatch();
  if (!isHelpOnly) {
    commandStopwatch.start();
  }
  if (estimatedSeconds != null && !isHelpOnly) {
    progress = EstimatedProgress(estimatedSeconds: estimatedSeconds)..start();
  }
  try {
    await runner.run(commandArgs);
    progress?.complete();
    _printCommandElapsed(
      commandArgs: commandArgs,
      elapsed: commandStopwatch.elapsed,
      estimatedSeconds: estimatedSeconds,
      isHelpOnly: isHelpOnly,
      failed: false,
    );
  } catch (e) {
    progress?.stop();
    _printCommandElapsed(
      commandArgs: commandArgs,
      elapsed: commandStopwatch.elapsed,
      estimatedSeconds: estimatedSeconds,
      isHelpOnly: isHelpOnly,
      failed: true,
    );
    rethrow;
  }
}

void _printCommandElapsed({
  required List<String> commandArgs,
  required Duration elapsed,
  required int? estimatedSeconds,
  required bool isHelpOnly,
  required bool failed,
}) {
  if (isHelpOnly) return;

  final name = describeMetaxCommand(commandArgs);
  final time = formatElapsedDuration(elapsed);
  final estimate =
      estimatedSeconds == null ? '' : '（预估 ${estimatedSeconds}s）';
  final status = failed ? '失败' : '完成';
  loggerInfo('命令$status: $name · 用时 $time$estimate');
}
