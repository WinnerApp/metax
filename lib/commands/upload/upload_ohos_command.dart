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

  UploadOhosCommand() {
    argParser.addOption(
      'app',
      help: '已签名的 .app 文件路径；不传则由 fastlane 自动查找最新产物',
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
}
