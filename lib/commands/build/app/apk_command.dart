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

    final gradlew = File(join(androidDir.path, 'gradlew'));
    if (!gradlew.existsSync()) {
      throw Exception('gradlew文件不存在: ${gradlew.path}');
    }

    // Flutter 工具偶发往宿主工程写入该文件，与 AAR 内同名类冲突，打包前删掉。
    final generatedPluginRegistrant = File(
      join(
        androidDir.path,
        'app',
        'src',
        'main',
        'java',
        'io',
        'flutter',
        'plugins',
        'GeneratedPluginRegistrant.java',
      ),
    );
    if (generatedPluginRegistrant.existsSync()) {
      generatedPluginRegistrant.deleteSync();
      loggerWarning(
        '已删除干扰打包的 GeneratedPluginRegistrant.java: '
        '${generatedPluginRegistrant.path}',
      );
    }

    /// ./gradlew assembleRelease
    await ProcessRunner().runProcess(
      ['./gradlew', 'assembleRelease'],
      workingDirectory: androidDir,
      printOutput: true,
    );

    loggerSuccess('apk打包完成');
  }
}
