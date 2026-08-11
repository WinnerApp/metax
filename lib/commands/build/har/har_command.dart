import 'package:args/command_runner.dart';
import 'package:meta_tool/commands/build/har/flutter_har_command.dart';
import 'package:meta_tool/commands/build/har/unity_har_command.dart';

class HarCommand extends Command {
  @override
  String get description => '打包 Flutter / Unity HAR（鸿蒙）';

  @override
  String get name => 'har';

  HarCommand() {
    addSubcommand(FlutterHarCommand());
    addSubcommand(UnityHarCommand());
  }
}
