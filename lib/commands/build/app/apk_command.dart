import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:meta_tool/common.dart';
import 'package:meta_tool/define.dart';
import 'package:path/path.dart';
import 'package:process_runner/process_runner.dart';

class ApkCommand extends Command {
  @override
  String get description => '打包Android的apk';

  @override
  String get name => 'apk';

  @override
  Future<void> run() async {
    final androidDir = appHomeDir.androidDir;
    if (!androidDir.existsSync()) {
      throw Exception('android目录不存在: ${androidDir.path}');
    }
    final gradlewName = Platform.isWindows ? 'gradlew.bat' : 'gradlew';
    final gradlew = File(join(androidDir.path, gradlewName));
    if (!gradlew.existsSync()) {
      throw Exception('gradlew文件不存在: ${gradlew.path}');
    }

    /// ./gradlew assembleRelease
    await ProcessRunner().runProcess(
      [gradlewName, 'assembleRelease'],
      workingDirectory: androidDir,
      printOutput: true,
    );

    loggerSuccess('apk打包完成');
  }
}
