import 'package:args/command_runner.dart';
import 'package:meta_tool/commands/build/build_command.dart';
import 'package:meta_tool/commands/cache/cache_command.dart';
import 'package:meta_tool/commands/init/init.dart';
import 'package:meta_tool/commands/upload/upload_command.dart';

Future<void> main(List<String> arguments) async {
  final runner = CommandRunner('metax', '一款棉宇宙开发和发布工具')
    ..addCommand(InitCommand())
    ..addCommand(BuildCommand())
    ..addCommand(UploadCommand())
    ..addCommand(CacheCommand());
  runner.argParser.addOption(
    'version',
    help: '版本号',
    callback: (p0) {
      print('v0.0.15');
    },
  );
  await runner.run(arguments);
}
