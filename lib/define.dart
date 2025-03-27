import 'dart:io';

import 'package:color_logger/color_logger.dart';
import 'package:meta_tool/app_home_dir.dart';
import 'package:path/path.dart';

final logger = ColorLogger();

enum BuildConfiguration {
  debug('debug'),
  release('release');

  const BuildConfiguration(this.value);
  final String value;
}

enum BuildPlatform {
  ios('ios'),
  android('android');

  const BuildPlatform(this.value);
  final String value;
}

enum BuildType {
  framework('framework'),
  aar('aar'),
  library('library');

  const BuildType(this.value);
  final String value;
}

enum BuildLibrary {
  flutter('flutter'),
  unity('unity');

  const BuildLibrary(this.value);
  final String value;
}

enum BuildPublish {
  test('test'),
  store('store');

  const BuildPublish(this.value);
  final String value;
}

enum MockType {
  iosUnityLibrary,
  androidUnityLibrary,
  flutterAar,
  flutterFramework,
  unityAar,
  unityFramework,
  ipa,
  apk;

  Directory mockDir(AppHomeDir appHomeDir) {
    final mockDir = Directory(join(appHomeDir.workspace, 'ignores', 'mock'));
    return switch (this) {
      MockType.iosUnityLibrary => Directory(join(
          mockDir.path,
          'ios_unity_library',
        )),
      MockType.androidUnityLibrary => Directory(join(
          mockDir.path,
          'android_unity_library',
        )),
      MockType.flutterAar => Directory(join(
          mockDir.path,
          'flutter_aar',
        )),
      MockType.flutterFramework => Directory(join(
          mockDir.path,
          'flutter_framework',
        )),
      MockType.unityAar => Directory(join(
          mockDir.path,
          'unity_aar',
        )),
      MockType.unityFramework => Directory(join(
          mockDir.path,
          'unity_framework',
        )),
      MockType.ipa => Directory(join(mockDir.path, 'meta_app_ipa')),
      MockType.apk => Directory(join(mockDir.path, 'meta_app_apk')),
    };
  }

  Directory sourceCacheDir(AppHomeDir appHomeDir) {
    return switch (this) {
      MockType.iosUnityLibrary => Directory(join(
          appHomeDir.iosDir.path,
          'UnityLibrary',
        )),
      MockType.androidUnityLibrary => Directory(join(
          appHomeDir.androidDir.path,
          'unityLibrary',
        )),
      MockType.flutterAar => Directory(join(
          appHomeDir.flutterDir.path,
          'build',
          'hots',
        )),
      MockType.flutterFramework => Directory(join(
          appHomeDir.flutterDir.path,
          'build',
          'ios',
          'framework',
          'Release',
        )),
      MockType.unityAar => Directory(join(
          appHomeDir.workspace,
          'build',
          'unityLibrary',
          'outputs',
          'aar',
        )),
      MockType.unityFramework => Directory(join(
          appHomeDir.iosDir.path,
          'UnityLibrary',
          'build',
          'Release-iphoneos',
        )),
      MockType.ipa => Directory(join(
          appHomeDir.iosDir.path,
          'build',
          'ios',
          'ipa',
        )),
      MockType.apk => throw UnimplementedError(),
    };
  }
}

late AppHomeDir appHomeDir;
late bool useMock;
