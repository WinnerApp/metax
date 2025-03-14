import 'package:meta_tool/common.dart';

class UnityEnvironment {
  late String unityWorkspace;
  late String iosUnityPath;
  late String androidUnityPath;
  late String enginePath;
  UnityEnvironment() {
    unityWorkspace = readEnv('UNITY_WORKSPACE');
    iosUnityPath = readEnv('IOS_UNITY_PATH');
    androidUnityPath = readEnv('ANDROID_UNITY_PATH');
    enginePath = readEnv('UNITY_ENGINE_PATH');
  }
}
