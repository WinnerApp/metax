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
  android('android'),
  ohos('ohos');

  const BuildPlatform(this.value);
  final String value;
}

enum BuildType {
  framework('framework'),
  aar('aar'),
  library('library'),
  har('har');

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
  ohosUnityLibrary,
  flutterAar,
  flutterHar,
  flutterFramework,
  unityAar,
  unityHar,
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
      MockType.ohosUnityLibrary => Directory(join(
          mockDir.path,
          'ohos_unity_library',
        )),
      MockType.flutterAar => Directory(join(
          mockDir.path,
          'flutter_aar',
        )),
      MockType.flutterHar => Directory(join(
          mockDir.path,
          'flutter_har',
        )),
      MockType.flutterFramework => Directory(join(
          mockDir.path,
          'flutter_framework',
        )),
      MockType.unityAar => Directory(join(
          mockDir.path,
          'unity_aar',
        )),
      MockType.unityHar => Directory(join(
          mockDir.path,
          'unity_har',
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
          appHomeDir.unityAndroidDir.path,
          'unityLibrary',
        )),
      MockType.ohosUnityLibrary => Directory(join(
          appHomeDir.ohosDir.path,
          'unityLibrary',
        )),
      MockType.flutterAar => Directory(join(
          appHomeDir.flutterDir.path,
          'build',
          'hots',
        )),
      MockType.flutterHar => Directory(join(
          appHomeDir.ohosDir.path,
          'aar',
          'flutter',
          'release',
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
      MockType.unityHar => Directory(join(
          appHomeDir.ohosDir.path,
          'aar',
          'unity',
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
late String? customUnityPath;
late bool isUseCache;
late bool isUseFlutterCache;
late bool isUseUnityCache;
late bool skipGitPull;

/// 当前构建库是否允许使用缓存（全局开关 + 分库开关同时生效）
bool isLibraryCacheEnabled(BuildLibrary library) {
  if (!isUseCache) return false;
  return switch (library) {
    BuildLibrary.flutter => isUseFlutterCache,
    BuildLibrary.unity => isUseUnityCache,
  };
}
