import 'dart:io';

import 'package:meta_tool/commands/upload/upload_app_command.dart';
import 'package:meta_tool/commands/upload/upload_app_environment.dart';
import 'package:meta_tool/common.dart';
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
      ],
      workingDirectory: appHomeDir.androidDir,
    );
  }

  @override
  Future<void> uploadApp({required String log}) async {
    await buildAppRunner.runProcess(
      [
        'metax',
        'upload',
        'apk',
        '--apk',
        apkPath,
        '--log',
        log,
      ],
      workingDirectory: appHomeDir.androidDir,
    );
  }

  String get apkPath => join(
        workspace,
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
  ) async {
    final channel = 'AppStore';
    final buildName = environment.buildName;
    final buildNumber = environment.buildNumber.toString();
    final copyDir = Directory(join(
      environment.workspace,
      'ignore_dir',
      'android',
      'apk',
    ));

    if (!await copyDir.exists()) {
      await copyDir.create(recursive: true);
    }
    await copyFile(
      File(apkPath),
      File(join(copyDir.path, '${channel}_${buildName}_$buildNumber.apk')),
    );
  }

  @override
  Future<void> sendLog(
      {required String log, required UploadAppEnvironment environment}) async {
    await sendTextToWeixinWebhooks(log, environment.androidHookUrl);
  }
}
