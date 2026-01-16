import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:meta_tool/common.dart';
import 'package:meta_tool/define.dart';

class UploadIpaCommand extends Command {
  @override
  String get description => '上传ipa';

  @override
  String get name => 'ipa';

  UploadIpaCommand() {
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
    String ipa = argResults?['ipa'];
    String? log = argResults?['log'];
    if (!File(ipa).existsSync()) {
      throw Exception('$ipa文件不存在');
    }

    await runProcessChecked(
      [
        'fastlane',
        'upload_testflight',
        'ipa:$ipa',
        'changelog:\'$log\'',
      ],
      workingDirectory: appHomeDir.iosDir,
      printOutput: true,
    );
    loggerSuccess('上传成功');
  }
}
