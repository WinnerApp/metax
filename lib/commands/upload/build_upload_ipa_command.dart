import 'dart:io';

import 'package:meta_tool/commands/upload/upload_app_command.dart';
import 'package:meta_tool/common.dart';
import 'package:meta_tool/define.dart';
import 'package:meta_tool/upload_app_environment.dart';
import 'package:path/path.dart';
import 'package:process_runner/process_runner.dart';

class BuildUploadIpaCommand extends UploadAppCommand {
  @override
  String get platform => 'ios';

  @override
  String get description => '上传ipa包';

  @override
  String get name => 'build_upload_ipa';

  @override
  String get buildType => 'framework';

  @override
  Future<void> buildApp() async {
    await ProcessRunner().runProcess(
      [
        'metax',
        'build',
        'app',
        'ipa',
        getUseMockCommand(),
      ],
      workingDirectory: appHomeDir.directory,
      printOutput: true,
    );
  }

  @override
  Future<void> uploadApp({
    required String log,
    required UploadAppEnvironment environment,
  }) async {
    await buildAppRunner.runProcess(
      [
        'metax',
        'upload',
        'ipa',
        '--ipa',
        ipaPath,
        '--log',
        log,
        getUseMockCommand(),
      ],
      workingDirectory: appHomeDir.directory,
      printOutput: true,
    );
  }

  String get ipaPath => join(
        appHomeDir.iosDir.path,
        'build',
        'ios',
        'ipa',
        'meta_winner_app.ipa',
      );

  @override
  Future<void> copyIpaOrApkToBuildDir(
    UploadAppEnvironment environment,
    String? copyDir,
  ) async {
    final channel = 'AppStore';
    final buildName = environment.buildName;
    final buildNumber = environment.buildNumber.toString();
    copyDir = copyDir ??
        join(
          environment.workspace,
          'ignore_dir',
          'ios',
          'ipa',
        );
    if (!await Directory(copyDir).exists()) {
      await Directory(copyDir).create(recursive: true);
    }
    await copyFile(
      File(ipaPath),
      File(join(copyDir, '${channel}_${buildName}_$buildNumber.ipa')),
    );
  }

  @override
  Future<void> sendLog(
      {required String log, required UploadAppEnvironment environment}) async {
    await sendTextToWeixinWebhooks(log, environment.iosHookUrl);
  }
}
