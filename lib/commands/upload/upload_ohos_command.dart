import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:meta_tool/common.dart';
import 'package:meta_tool/define.dart';
import 'package:process_runner/process_runner.dart';

class UploadOhosCommand extends Command {
  @override
  String get description => '上传鸿蒙 .app 到 AppGallery Connect 测试分发';

  @override
  String get name => 'ohos';

  /// AGC testDesc 最长 50 字符
  static const int _maxTestDescLength = 50;

  UploadOhosCommand() {
    argParser.addOption(
      'app',
      help: '已签名的 .app 文件路径；不传则由 fastlane 自动查找最新产物',
    );
    argParser.addOption(
      'log',
      help: '测试版本描述（来自自动化打包日志）；AGC 最长 50 字符，超长截断',
    );
    argParser.addFlag(
      'formal',
      help: '走正式发布：upload + submit_review（默认走测试分发 submit_test）',
      defaultsTo: false,
      negatable: false,
    );
    argParser.addFlag(
      'skip-submit',
      help: '仅上传，不提交审核/测试分发',
      defaultsTo: false,
      negatable: false,
    );
  }

  @override
  FutureOr? run() async {
    final ohosDir = appHomeDir.ohosDir;
    if (!ohosDir.existsSync()) {
      throw Exception('ohos目录不存在: ${ohosDir.path}');
    }

    final appPath = argResults?['app'] as String?;
    if (appPath != null && appPath.isNotEmpty) {
      if (!File(appPath).existsSync()) {
        throw Exception('$appPath 文件不存在');
      }
    }

    final formal = argResults?['formal'] as bool? ?? false;
    final skipSubmit = argResults?['skip-submit'] as bool? ?? false;
    final testDesc = _normalizeTestDesc(argResults?['log'] as String?);

    if (formal) {
      final uploadCommands = <String>[
        'fastlane',
        'harmony',
        'upload',
      ];
      if (appPath != null && appPath.isNotEmpty) {
        uploadCommands.add('app_path:$appPath');
      }
      await ProcessRunner().runProcess(
        uploadCommands,
        workingDirectory: ohosDir,
        printOutput: true,
      );
      if (!skipSubmit) {
        await ProcessRunner().runProcess(
          ['fastlane', 'harmony', 'submit_review'],
          workingDirectory: ohosDir,
          printOutput: true,
        );
      }
    } else if (!skipSubmit) {
      final commands = <String>[
        'fastlane',
        'harmony',
        'submit_test',
      ];
      if (appPath != null && appPath.isNotEmpty) {
        commands.add('app_path:$appPath');
      }
      if (testDesc != null) {
        commands.add('test_desc:$testDesc');
        loggerDebug('AGC testDesc: $testDesc');
      }
      await ProcessRunner().runProcess(
        commands,
        workingDirectory: ohosDir,
        printOutput: true,
      );
    } else {
      loggerWarning('已跳过测试分发提交（--skip-submit）');
    }

    loggerSuccess('鸿蒙上传成功');
  }

  /// 去掉首尾空白；超长截断到 AGC 上限；空则返回 null（走脚本默认 CI 包名）
  String? _normalizeTestDesc(String? raw) {
    final trimmed = raw?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    if (trimmed.length <= _maxTestDescLength) {
      return trimmed;
    }
    final truncated = trimmed.substring(0, _maxTestDescLength);
    loggerWarning(
      '测试描述超过 $_maxTestDescLength 字符，已截断: $truncated',
    );
    return truncated;
  }
}
