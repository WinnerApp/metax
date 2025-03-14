import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:meta_tool/commands/build/build_command.dart';
import 'package:meta_tool/commands/cache/cache_command.dart';
import 'package:meta_tool/commands/init/init.dart';
import 'package:meta_tool/commands/upload/upload_command.dart';

Future<void> main(List<String> arguments) async {
  print(Directory.current.path);
  final runner = CommandRunner('metax', '欢迎使用棉宇宙工具')
    ..addCommand(InitCommand())
    ..addCommand(BuildCommand())
    ..addCommand(UploadCommand())
    ..addCommand(CacheCommand());
  await runner.run(arguments);
}
