import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:meta_tool/common.dart';
import 'package:path/path.dart';

class UploadAppCommand extends Command {
  @override
  String get name => 'app';

  @override
  String get description => '上传安装包';

  UploadAppCommand() {
    argParser.addOption('workspace', abbr: 's', help: '打包App的workspace路径,默认为当前目录');
    argParser.addOption('platform', abbr: 'p', help: '打包平台', allowed: ['ios', 'android']);
  }


  @override
  FutureOr? run() async{
    final workspace = argResults?['workspace'] ?? Directory.current.path;
    final platform = argResults?['platform'];

    if (platform == null) {
      loggerError('请指定打包平台');
      return;
    }

    final flutterDir = Directory(join(workspace, 'metaapp_flutter'));
    final iosDir = Directory(join(workspace, 'ios'));
    final androidDir = Directory(join(workspace, 'android'));

    if (!flutterDir.existsSync() && !iosDir.existsSync() && !androidDir.existsSync()) {
      loggerError('打包目录不正确！');
      return;
    }

    
    
  }
  
}