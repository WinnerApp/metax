import 'dart:async';

import 'package:args/command_runner.dart';
import 'package:meta_tool/common.dart';
import 'package:meta_tool/define.dart';
import 'package:process_runner/process_runner.dart';

class BuildUploadOhosCommand extends Command {
  @override
  String get description => '一键打包鸿蒙 .app 并上传 AppGallery Connect 测试分发';

  @override
  String get name => 'build_upload_ohos';

  BuildUploadOhosCommand() {
    argParser.addOption(
      'version-name',
      help: '版本号 versionName，不传则由 fastlane 交互询问',
    );
    argParser.addFlag(
      'formal',
      help: '走正式发布审核（默认测试分发）',
      defaultsTo: false,
      negatable: false,
    );
    argParser.addFlag(
      'skip-submit',
      help: '仅打包并上传，不提交审核',
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

    final versionName = argResults?['version-name'] as String?;
    final formal = argResults?['formal'] as bool? ?? false;
    final skipSubmit = argResults?['skip-submit'] as bool? ?? false;

    final commands = <String>[
      'fastlane',
      'harmony',
      'release_ohos',
      'yes:true',
    ];
    if (versionName != null && versionName.isNotEmpty) {
      commands.add('version_name:$versionName');
    }
    if (formal) {
      commands.add('formal_release:true');
    }
    if (skipSubmit) {
      commands.add('skip_submit:true');
    }

    await ProcessRunner().runProcess(
      commands,
      workingDirectory: ohosDir,
      printOutput: true,
    );

    loggerSuccess('鸿蒙打包上传完成');
  }
}
