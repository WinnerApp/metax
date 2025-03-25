import 'dart:io';

import 'package:path/path.dart';

class AppHomeDir {
  final String workspace;

  AppHomeDir(this.workspace);

  Directory get iosDir => Directory(join(workspace, 'ios'));
  Directory get androidDir => Directory(join(workspace, 'android'));
  Directory get flutterDir => Directory(join(workspace, 'metaapp_flutter'));
}
