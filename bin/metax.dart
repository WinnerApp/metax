import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:meta_tool/app_home_dir.dart';
import 'package:meta_tool/commands/build/build_command.dart';
import 'package:meta_tool/commands/cache/cache_command.dart';
import 'package:meta_tool/commands/init/init.dart';
import 'package:meta_tool/commands/publish/publish_command.dart';
import 'package:meta_tool/commands/test/test_command.dart';
import 'package:meta_tool/commands/upload/upload_command.dart';
import 'package:meta_tool/define.dart';

Future<void> main(List<String> arguments) async {
  final runner = CommandRunner('metax', '一款棉宇宙开发和发布工具')
    ..addCommand(InitCommand())
    ..addCommand(BuildCommand())
    ..addCommand(UploadCommand())
    ..addCommand(CacheCommand())
    ..addCommand(PublishCommand())
    ..addCommand(TestCommand());
  runner.argParser.addOption(
    'workspace',
    help: 'app运行目录，默认使用当前目录',
    defaultsTo: Directory.current.path,
    callback: (value) {
      appHomeDir = AppHomeDir(value!);
    },
  );
  runner.argParser.addFlag(
    'isUseMock',
    help: '是否使用mock数据，默认不使用',
    defaultsTo: false,
    callback: (value) {
      useMock = value;
    },
  );
  runner.argParser.addOption(
    'unityPath',
    help: '自定义当前环境的Unity版本路径',
    callback: (p0) {
      customUnityPath = p0;
    },
  );
  runner.argParser.addFlag(
    'isUseCache',
    help: '是否使用缓存',
    defaultsTo: true,
    callback: (value) {
      isUseCache = value;
    },
  );
  runner.argParser.addFlag(
    'skipGitPull',
    help: '跳过拉取最新代码，使用本地提交',
    defaultsTo: false,
    callback: (value) {
      skipGitPull = value;
    },
  );
  try {
    await runner.run(arguments);
  } catch (e, stackTrace) {
    print('Error: $e');
    print('Stack trace: $stackTrace');
    exit(1);
  }
}
