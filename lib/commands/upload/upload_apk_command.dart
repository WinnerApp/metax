import 'dart:io';

import 'package:meta_tool/cache/framework_aar_cache.dart';
import 'package:meta_tool/cache/unity_cache.dart';
import 'package:meta_tool/commands/upload/upload_app_command.dart';
import 'package:meta_tool/commands/upload/upload_app_environment.dart';
import 'package:meta_tool/define.dart';
import 'package:path/path.dart';
import 'package:process_runner/process_runner.dart';

class UploadApkCommand extends UploadAppCommand {
  UploadApkCommand()
      : super(environment: UploadAppEnvironment(platform: 'android'));

  @override
  String get description => '上传apk包';

  @override
  String get name => 'apk';

  @override
  UnityCache get unityCache => UnityCache(platform: BuildPlatform.android);

  @override
  FrameworkAarCache get flutterFrameworkAarCache => FrameworkAarCache(
        platform: BuildPlatform.android,
        configuration: BuildConfiguration.release,
        type: BuildType.aar,
        library: BuildLibrary.flutter,
      );

  @override
  FrameworkAarCache get unityFrameworkAarCache => FrameworkAarCache(
        platform: BuildPlatform.android,
        configuration: BuildConfiguration.release,
        type: BuildType.aar,
        library: BuildLibrary.unity,
      );

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
}
