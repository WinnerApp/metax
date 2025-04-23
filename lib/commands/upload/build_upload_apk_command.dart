import 'dart:io';

import 'package:meta_tool/commands/upload/upload_app_command.dart';
import 'package:meta_tool/common.dart';
import 'package:meta_tool/define.dart';
import 'package:meta_tool/upload_app_environment.dart';
import 'package:path/path.dart';
import 'package:process_runner/process_runner.dart';

class BuildUploadApkCommand extends UploadAppCommand {
  @override
  String get platform => 'android';
  @override
  String get description => '上传apk包';

  @override
  String get name => 'build_upload_apk';

  @override
  String get buildType => 'aar';

  @override
  Future<void> buildApp() async {
    await ProcessRunner().runProcess(
      [
        'metax',
        'build',
        'app',
        'apk',
        getUseMockCommand(),
      ],
      workingDirectory: appHomeDir.directory,
      printOutput: true,
    );
  }

  @override
  Future<void> uploadApp(
      {required String log, required UploadAppEnvironment environment}) async {
    buildAppRunner.environment['ZEALOT_CHANNEL_KEY'] =
        environment.zealotChannelKey;
    await buildAppRunner.runProcess(
      [
        'metax',
        'upload',
        'apk',
        '--apk',
        apkPath,
        '--log',
        log,
        getUseMockCommand(),
      ],
      workingDirectory: appHomeDir.directory,
      printOutput: true,
    );
  }

  String get apkPath => join(
        appHomeDir.workspace,
        'build',
        'app',
        'outputs',
        'apk',
        'release',
        'app-release.apk',
      );

  @override
  Future<void> copyIpaOrApkToBuildDir(
    UploadAppEnvironment environment,
    String? copyDir,
  ) async {
    final channel = environment.androidChannel;
    final buildName = environment.buildName;
    final buildNumber = environment.buildNumber.toString();
    copyDir = copyDir ??
        join(
          environment.workspace,
          'ignore_dir',
          'android',
          'apk',
        );

    if (!await Directory(copyDir).exists()) {
      await Directory(copyDir).create(recursive: true);
    }
    await copyFile(
      File(apkPath),
      File(join(copyDir, '${channel}_${buildName}_$buildNumber.apk')),
    );
  }

  @override
  Future<void> sendLog(
      {required String log, required UploadAppEnvironment environment}) async {
    await sendTextToWeixinWebhooks(log, environment.androidHookUrl);
  }
}
