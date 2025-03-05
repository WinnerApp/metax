import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:meta_tool/commands/init/init.dart';

void main(List<String> arguments) {
  print(Directory.current.path);
  CommandRunner('mool', '欢迎使用棉宇宙工具')
    ..addCommand(InitCommand())
    ..run(arguments);
}
