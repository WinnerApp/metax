import 'package:args/command_runner.dart';
import 'package:meta_tool/commands/build/unity/android_unity_cache_command.dart';
import 'package:meta_tool/commands/build/unity/ios_unity_cache_command.dart';
import 'package:meta_tool/commands/build/unity/ohos_unity_cache_command.dart';

class UnityCacheCommand extends Command {
  @override
  String get description => '导出Unity缓存';

  @override
  String get name => 'unity_cache';

  UnityCacheCommand() {
    addSubcommand(IosUnityCacheCommand());
    addSubcommand(AndroidUnityCacheCommand());
    addSubcommand(OhosUnityCacheCommand());
  }
}
