import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:meta_tool/common.dart';
import 'package:process_runner/process_runner.dart';

class UploadIpaCommand extends Command {
  @override
  String get description => '上传ipa';

  @override
  String get name => 'ipa';

  UploadIpaCommand() {
    argParser.addOption(
      'workspace',
      help: 'ios项目目录,默认为当前目录',
    );

    argParser.addOption(
      'ipa',
      help: 'ipa文件路径',
      mandatory: true,
    );

    argParser.addOption(
      'log',
      help: '构建日志',
    );
  }

  @override
  Future run() async {
    String workspace = argResults?['workspace'] ?? Directory.current.path;
    String ipa = argResults?['ipa'];
    String? log = argResults?['log'];
    if (!File(ipa).existsSync()) {
      throw Exception('$ipa文件不存在');
    }

    await ProcessRunner().runProcess(
      [
        'fastlane',
        'upload_testflight',
        'ipa:$ipa',
        'changelog:\'$log\'',
      ],
      workingDirectory: Directory(workspace),
    );
    loggerSuccess('上传成功');
  }
}
