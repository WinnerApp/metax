import 'package:args/command_runner.dart';
import 'package:meta_tool/commands/publish/meta_command.dart';

class PublishCommand extends Command {
  @override
  String get description => '发布命令';

  @override
  String get name => 'publish';

  PublishCommand() {
    addSubcommand(MetaCommand());
  }
}
