import 'dart:io';
import 'package:meta_tool/commands/upload/upload_app_command.dart';
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
  Directory get unityProjectDir => Directory(join(
        environment.workspace,
        environment.androidUnityPath,
      ));

  @override
  Directory get unityFrameworkAarDir => Directory(join(
        environment.workspace,
        'android',
        'aar',
        'unity',
      ));

  @override
  Future<void> buildUnityStaticLibrary() async {
    await ProcessRunner().runProcess(
      [
        'metax',
        'build',
        'aar',
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
        'aar',
        'flutter',
      ],
      workingDirectory: flutterProjectDir,
    );
  }

  @override
  Directory get flutterFrameworkAarDir => Directory(join(
        environment.workspace,
        'android',
        'aar',
        'flutter',
      ));

  @override
  Future<void> buildApp() async {
    await ProcessRunner().runProcess(
      [
        'metax',
        'build',
        'app',
        'apk',
      ],
      workingDirectory: androidProjectDir,
    );
  }

  @override
  Future<void> uploadApp({required String log}) async {
    await ProcessRunner().runProcess(
      [
        'metax',
        'upload',
        'apk',
        '--apk',
        apkPath,
        '--log',
        log,
      ],
      workingDirectory: androidProjectDir,
    );
  }

  String get apkPath => join(
        environment.workspace,
        'build',
        'app',
        'outputs',
        'apk',
        'release',
        'app-release.apk',
      );

  @override
  Future<void> copyIpaOrApkToBuildDir() async {
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
  Future<void> sendLog({required String log}) async {
    await sendTextToWeixinWebhooks(log, environment.androidHookUrl);
  }
}
