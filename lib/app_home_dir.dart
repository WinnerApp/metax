import 'dart:io';

import 'package:path/path.dart';

class AppHomeDir {
  final String workspace;

  AppHomeDir(this.workspace);

  Directory get iosDir => Directory(join(workspace, 'ios'));
  Directory get androidDir => Directory(join(workspace, 'android'));
  Directory get ohosDir => Directory(join(workspace, 'ohos'));
  /// 独立打包 Unity HAR 的鸿蒙工程壳（与 ohos 宿主解耦）
  Directory get unityOhosDir => Directory(join(workspace, 'unityOhos'));
  Directory get flutterDir => Directory(join(workspace, 'metaapp_flutter'));
  Directory get directory => Directory(workspace);
}
