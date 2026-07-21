import 'dart:io';

import 'package:meta_tool/app_home_dir.dart';
import 'package:meta_tool/common.dart';
import 'package:path/path.dart';

class UnityEnvironment {
  final String unityWorkspace;
  final String iosUnityPath;
  final String androidUnityPath;
  final String? ohosUnityPath;
  final String unityEnginePath;
  final String? tuanjieEnginePath;

  String get iosUnityWorkspace => join(unityWorkspace, iosUnityPath);
  String get androidUnityWorkspace => join(unityWorkspace, androidUnityPath);
  String get ohosUnityWorkspace {
    final path = ohosUnityPath;
    if (path == null || path.isEmpty) {
      throw '请设置环境变量 【OHOS_UNITY_PATH】 请先执行metax init app_environment';
    }
    return join(unityWorkspace, path);
  }

  String get requiredTuanjieEnginePath {
    final path = tuanjieEnginePath;
    if (path == null || path.isEmpty) {
      throw '请设置环境变量 【TUANJIE_ENGINE_PATH】 请先执行metax init app_environment';
    }
    return path;
  }

  UnityEnvironment({
    required this.unityWorkspace,
    required this.iosUnityPath,
    required this.androidUnityPath,
    required this.ohosUnityPath,
    required this.unityEnginePath,
    required this.tuanjieEnginePath,
  });

  factory UnityEnvironment.fromEnvironment(AppHomeDir appHomeDir) {
    final environment = loadAppEnvironment(appHomeDir);
    return UnityEnvironment(
      unityWorkspace: readEnv(
        'UNITY_WORKSPACE',
        environment: environment,
        throwMessage: '请先执行metax init app_environment',
      ),
      iosUnityPath: readEnv(
        'IOS_UNITY_PATH',
        environment: environment,
        throwMessage: '请先执行metax init app_environment',
      ),
      androidUnityPath: readEnv(
        'ANDROID_UNITY_PATH',
        environment: environment,
        throwMessage: '请先执行metax init app_environment',
      ),
      ohosUnityPath: environment['OHOS_UNITY_PATH'] ??
          Platform.environment['OHOS_UNITY_PATH'],
      unityEnginePath: readEnv(
        'UNITY_ENGINE_PATH',
        environment: environment,
        throwMessage: '请先执行metax init app_environment',
      ),
      tuanjieEnginePath: environment['TUANJIE_ENGINE_PATH'] ??
          Platform.environment['TUANJIE_ENGINE_PATH'],
    );
  }

  String getPlatfromUnityWorkspace(String platform) {
    return switch (platform) {
      'ios' => iosUnityWorkspace,
      'android' => androidUnityWorkspace,
      'ohos' => ohosUnityWorkspace,
      _ => throw Exception('不支持的平台: $platform'),
    };
  }

  /// iOS/Android 使用 Unity 引擎；鸿蒙使用团结引擎。
  String getEnginePath(String platform) {
    return switch (platform) {
      'ios' || 'android' => unityEnginePath,
      'ohos' => requiredTuanjieEnginePath,
      _ => throw Exception('不支持的平台: $platform'),
    };
  }
}
