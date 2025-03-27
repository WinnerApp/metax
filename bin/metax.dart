import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:meta_tool/app_home_dir.dart';
import 'package:meta_tool/commands/build/build_command.dart';
import 'package:meta_tool/commands/cache/cache_command.dart';
import 'package:meta_tool/commands/init/init.dart';
import 'package:meta_tool/commands/publish/publish_command.dart';
import 'package:meta_tool/commands/upload/upload_command.dart';
import 'package:meta_tool/define.dart';

Future<void> main(List<String> arguments) async {
  final runner = CommandRunner('metax', '一款棉宇宙开发和发布工具')
    ..addCommand(InitCommand())
    ..addCommand(BuildCommand())
    ..addCommand(UploadCommand())
    ..addCommand(CacheCommand())
    ..addCommand(PublishCommand());
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
  await runner.run(arguments);
}
