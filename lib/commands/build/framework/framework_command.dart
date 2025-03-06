import 'package:args/command_runner.dart';
import 'package:meta_tool/commands/build/framework/flutter_framework_command.dart';

class FrameworkCommand extends Command {
  @override
  String get description => '编译Flutter和Unity的Framework';

  @override
  String get name => 'framework';

  FrameworkCommand() {
    addSubcommand(FlutterFrameworkCommand());
  }
}
