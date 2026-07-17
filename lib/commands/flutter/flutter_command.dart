import 'package:args/command_runner.dart';
import 'package:meta_tool/commands/flutter/upgrade_flutter_command.dart';

class FlutterCommand extends Command {
  @override
  String get description => 'Flutter SDK / FVM 相关操作';

  @override
  String get name => 'flutter';

  FlutterCommand() {
    addSubcommand(UpgradeFlutterCommand());
  }
}
