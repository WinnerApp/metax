import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:meta_tool/common.dart';
import 'package:meta_tool/define.dart';
import 'package:path/path.dart';
import 'package:process_runner/process_runner.dart';

class OhosCommand extends Command {
  @override
  String get description => '打包鸿蒙 .app 安装包（上架/分发）';

  @override
  String get name => 'ohos';

  OhosCommand() {
    argParser.addOption(
      'version-name',
      help: '版本号 versionName，不传则由 fastlane 交互询问',
    );
  }

  @override
  Future<void> run() async {
    final ohosDir = appHomeDir.ohosDir;
    if (!ohosDir.existsSync()) {
      throw Exception('ohos目录不存在: ${ohosDir.path}');
    }

    final fastlaneDir = Directory(join(ohosDir.path, 'fastlane'));
    if (!fastlaneDir.existsSync()) {
      throw Exception('ohos/fastlane目录不存在: ${fastlaneDir.path}');
    }

    final versionName = argResults?['version-name'] as String?;
    final commands = <String>[
      'fastlane',
      'harmony',
      'build_ohos_app',
      'yes:true',
    ];
    if (versionName != null && versionName.isNotEmpty) {
      commands.add('version_name:$versionName');
    }

    await ProcessRunner().runProcess(
      commands,
      workingDirectory: ohosDir,
      printOutput: true,
    );

    loggerSuccess('鸿蒙 .app 打包完成');
  }
}
