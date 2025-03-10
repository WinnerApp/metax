import 'dart:io';

import 'package:meta_tool/cache/framework_aar_cache.dart';
import 'package:meta_tool/cache/unity_cache.dart';
import 'package:meta_tool/commands/upload/upload_app_command.dart';
import 'package:meta_tool/commands/upload/upload_app_environment.dart';
import 'package:meta_tool/define.dart';
import 'package:path/path.dart';
import 'package:process_runner/process_runner.dart';

class UploadIpaCommand extends UploadAppCommand {
  UploadIpaCommand()
      : super(environment: UploadAppEnvironment(platform: 'ios'));

  @override
  String get description => '上传ipa包';

  @override
  String get name => 'ipa';

  @override
  UnityCache get unityCache => UnityCache(platform: BuildPlatform.ios);

  @override
  FrameworkAarCache get flutterFrameworkAarCache => FrameworkAarCache(
        platform: BuildPlatform.ios,
        configuration: BuildConfiguration.release,
        type: BuildType.framework,
        library: BuildLibrary.flutter,
      );

  @override
  FrameworkAarCache get unityFrameworkAarCache => FrameworkAarCache(
        platform: BuildPlatform.ios,
        configuration: BuildConfiguration.release,
        type: BuildType.framework,
        library: BuildLibrary.unity,
      );

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
}
