import 'dart:io';

import 'package:path/path.dart';

class AppHomeDir {
  final String workspace;

  AppHomeDir({required this.workspace}) {
    if (!iosDir.existsSync()) {
      throw '[$iosDir]目录不存在';
    }
    if (!androidDir.existsSync()) {
      throw '[$androidDir]目录不存在';
    }
    if (!flutterDir.existsSync()) {
      throw '[$flutterDir]目录不存在';
    }
  }

  Directory get iosDir => Directory(join(workspace, 'ios'));
  Directory get androidDir => Directory(join(workspace, 'android'));
  Directory get flutterDir => Directory(join(workspace, 'flutter'));
}
