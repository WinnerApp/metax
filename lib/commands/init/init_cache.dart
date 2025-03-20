import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:meta_tool/app_home_dir.dart';
import 'package:meta_tool/common.dart';
import 'package:process_runner/process_runner.dart';

class InitCacheCommand extends Command {
  @override
  String get description => '初始化缓存';

  @override
  String get name => 'cache';

  InitCacheCommand() {
    argParser.addOption(
      'workspace',
      help: 'App工作目录',
      defaultsTo: Directory.current.path,
    );
  }

  @override
  FutureOr? run() async {
    final workspace = argResults?['workspace'];
    final appHomeDir = AppHomeDir(workspace: workspace);
    loggerDebug('正在初始化iOS静态库');
    await ProcessRunner().runProcess(
      [
        'metax',
        'cache',
        'use',
        '--buildPlatform',
        'ios',
        '--buildLibrary',
        'flutter',
        '--buildType',
        'framework',
      ],
      workingDirectory: Directory(appHomeDir.workspace),
    );
    await ProcessRunner().runProcess(
      [
        'metax',
        'cache',
        'use',
        '--buildPlatform',
        'ios',
        '--buildLibrary',
        'unity',
        '--buildType',
        'framework',
      ],
      workingDirectory: Directory(appHomeDir.workspace),
    );
    loggerDebug('正在初始化Android静态库');
    await ProcessRunner().runProcess(
      [
        'metax',
        'cache',
        'use',
        '--buildPlatform',
        'android',
        '--buildLibrary',
        'flutter',
        '--buildType',
        'aar',
      ],
      workingDirectory: Directory(appHomeDir.workspace),
    );
    await ProcessRunner().runProcess(
      [
        'metax',
        'cache',
        'use',
        '--buildPlatform',
        'android',
        '--buildLibrary',
        'unity',
        '--buildType',
        'aar',
      ],
      workingDirectory: Directory(appHomeDir.workspace),
    );
    loggerDebug('初始化缓存完成');
  }
}
