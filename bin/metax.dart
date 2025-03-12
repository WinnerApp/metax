import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:meta_tool/commands/build/build_command.dart';
import 'package:meta_tool/commands/init/init.dart';
import 'package:meta_tool/commands/upload/upload_command.dart';

void main(List<String> arguments) {
  print(Directory.current.path);
  CommandRunner('metax', '欢迎使用棉宇宙工具')
    // ..addCommand(InitCommand())
    ..addCommand(BuildCommand())
    ..addCommand(UploadCommand())
    ..run(arguments);
}
