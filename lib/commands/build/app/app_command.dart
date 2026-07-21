import 'package:args/command_runner.dart';
import 'package:meta_tool/commands/build/app/apk_command.dart';
import 'package:meta_tool/commands/build/app/hap_command.dart';
import 'package:meta_tool/commands/build/app/ipa_command.dart';
import 'package:meta_tool/commands/build/app/ohos_command.dart';

class AppCommand extends Command {
  @override
  String get description => '打包iOS、Android和鸿蒙的安装包';

  @override
  String get name => 'app';

  AppCommand() {
    addSubcommand(IpaCommand());
    addSubcommand(ApkCommand());
    addSubcommand(OhosCommand());
    addSubcommand(HapCommand());
  }
}
