import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:meta_tool/common.dart';
import 'package:path/path.dart';
import 'package:process_runner/process_runner.dart';

class ApkCommand extends Command {
  @override
  String get description => '打包Android的apk';

  @override
  String get name => 'apk';

  ApkCommand() {
    argParser.addOption('workspace', abbr: 's', help: 'android工程目录，默认使用当前目录');
  }

  @override
  Future<void> run() async {
    final workspace = argResults?['workspace'] ?? Directory.current.path;
    final workspaceDir = Directory(workspace);
    if (!workspaceDir.existsSync()) {
      throw Exception('workspace目录不存在: $workspace');
    }

    final gradlew = File(join(workspaceDir.path, 'gradlew'));
    if (!gradlew.existsSync()) {
      throw Exception('gradlew文件不存在: ${gradlew.path}');
    }

    /// ./gradlew assembleRelease
    await ProcessRunner().runProcess(
      ['./gradlew', 'assembleRelease'],
      workingDirectory: workspaceDir,
      printOutput: true,
    );

    loggerSuccess('apk打包完成');
  }
}
