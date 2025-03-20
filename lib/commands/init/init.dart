import 'package:args/command_runner.dart';
import 'package:meta_tool/commands/init/app_environment_command.dart';
import 'package:meta_tool/commands/init/branch.dart';
import 'package:meta_tool/commands/init/init_cache.dart';
import 'package:meta_tool/commands/init/project_command.dart';

class InitCommand extends Command {
  @override
  String get description => '初始化一些操作，比如工程';

  @override
  String get name => 'init';

  InitCommand() {
    addSubcommand(ProjectCommand());
    addSubcommand(BranchCommand());
    addSubcommand(InitCacheCommand());
    addSubcommand(AppEnvironmentCommand());
  }
}
