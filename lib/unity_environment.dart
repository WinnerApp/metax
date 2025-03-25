import 'package:meta_tool/app_home_dir.dart';
import 'package:meta_tool/common.dart';
import 'package:path/path.dart';

class UnityEnvironment {
  final String unityWorkspace;
  final String iosUnityPath;
  final String androidUnityPath;
  final String unityEnginePath;

  String get iosUnityWorkspace => join(unityWorkspace, iosUnityPath);
  String get androidUnityWorkspace => join(unityWorkspace, androidUnityPath);

  UnityEnvironment({
    required this.unityWorkspace,
    required this.iosUnityPath,
    required this.androidUnityPath,
    required this.unityEnginePath,
  });

  factory UnityEnvironment.fromEnvironment(AppHomeDir appHomeDir) {
    return UnityEnvironment(
      unityWorkspace: readAppEnv('UNITY_WORKSPACE', appHomeDir),
      iosUnityPath: readAppEnv('IOS_UNITY_PATH', appHomeDir),
      androidUnityPath: readAppEnv('ANDROID_UNITY_PATH', appHomeDir),
      unityEnginePath: readAppEnv('UNITY_ENGINE_PATH', appHomeDir),
    );
  }

  String getPlatfromUnityWorkspace(String platform) {
    if (platform == 'ios') {
      return iosUnityWorkspace;
    } else {
      return androidUnityWorkspace;
    }
  }
}
