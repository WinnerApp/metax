import 'package:args/command_runner.dart';
import 'package:meta_tool/commands/build/app/apk_command.dart';
import 'package:meta_tool/commands/build/app/ipa_command.dart';

class AppCommand extends Command {
  @override
  String get description => '打包iOS和Android的安装包';

  @override
  String get name => 'app';

  AppCommand() {
    addSubcommand(IpaCommand());
    addSubcommand(ApkCommand());
  }
}
