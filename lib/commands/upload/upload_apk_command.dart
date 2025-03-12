import 'dart:async';
import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:meta_tool/common.dart';
import 'package:process_runner/process_runner.dart';

class UploadApkCommand extends Command {
  @override
  String get description => '上传apk';

  @override
  String get name => 'apk';

  UploadApkCommand() {
    argParser.addOption(
      'workspace',
      help: 'android项目目录,默认为当前目录',
    );
    argParser.addOption(
      'apk',
      help: 'apk文件路径',
      mandatory: true,
    );
    argParser.addOption(
      'log',
      help: '构建日志',
    );
  }

  @override
  FutureOr? run() async {
    String workspace = argResults?['workspace'] ?? Directory.current.path;
    String apk = argResults?['apk'];
    String? log = argResults?['log'];
    if (!File(apk).existsSync()) {
      throw Exception('$apk文件不存在');
    }
    await ProcessRunner().runProcess(
      [
        'fastlane',
        'deploy',
        'apk:$apk',
        'changelog:\'$log\'',
      ],
      workingDirectory: Directory(workspace),
    );
    loggerSuccess('上传成功');
  }
}
