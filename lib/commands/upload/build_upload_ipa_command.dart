import 'dart:io';
import 'package:meta_tool/commands/upload/upload_app_command.dart';
import 'package:meta_tool/common.dart';
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
  Directory get unityProjectDir => Directory(join(
        environment.workspace,
        environment.iosUnityPath,
      ));

  @override
  Directory get unityFrameworkAarDir => Directory(join(
        environment.workspace,
        'ios',
        'Frameworks',
        'unity',
      ));

  @override
  Future<void> buildUnityStaticLibrary() async {
    await ProcessRunner().runProcess(
      [
        'metax',
        'build',
        'framework',
        'unity',
      ],
      workingDirectory: unityProjectDir,
    );
  }

  @override
  Future<void> buildFlutterStaticLibrary() async {
    await ProcessRunner().runProcess(
      [
        'metax',
        'build',
        'framework',
        'flutter',
      ],
      workingDirectory: flutterProjectDir,
    );
  }

  @override
  Directory get flutterFrameworkAarDir => Directory(
        join(
          environment.workspace,
          'ios',
          'Frameworks',
          'flutter',
        ),
      );

  @override
  Future<void> buildApp() async {
    await ProcessRunner().runProcess(
      [
        'metax',
        'build',
        'app',
        'ipa',
      ],
      workingDirectory: iosProjectDir,
    );
  }

  @override
  Future<void> uploadApp({required String log}) async {
    await ProcessRunner().runProcess(
      [
        'metax',
        'upload',
        'ipa',
        '--ipa',
        ipaPath,
        '--log',
        log,
      ],
      workingDirectory: iosProjectDir,
    );
  }

  String get ipaPath => join(
        environment.workspace,
        'build',
        'ios',
        'ipa',
        'meta_winner_app.ipa',
      );

  @override
  Future<void> copyIpaOrApkToBuildDir() async {
    final channel = 'AppStore';
    final buildName = environment.buildName;
    final buildNumber = environment.buildNumber.toString();
    final copyDir = Directory(join(
      environment.workspace,
      'ignore_dir',
      'ios',
      'ipa',
    ));
    if (!await copyDir.exists()) {
      await copyDir.create(recursive: true);
    }
    await copyFile(
      File(ipaPath),
      File(join(copyDir.path, '${channel}_${buildName}_$buildNumber.ipa')),
    );
  }

  @override
  Future<void> sendLog({required String log}) async {
    await sendTextToWeixinWebhooks(log, environment.iosHookUrl);
  }
}
