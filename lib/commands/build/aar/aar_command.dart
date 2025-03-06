import 'package:args/command_runner.dart';
import 'package:meta_tool/commands/build/aar/flutter_aar_command.dart';
import 'package:meta_tool/commands/build/aar/unity_aar_command.dart';

class AarCommand extends Command {
  @override
  String get description => '打包flutter个unity的aar';

  @override
  String get name => 'aar';

  AarCommand() {
    addSubcommand(FlutterAarCommand());
    addSubcommand(UnityAarCommand());
  }
}
