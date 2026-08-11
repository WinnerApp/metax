import 'package:args/command_runner.dart';
import 'package:meta_tool/commands/build/aar/aar_command.dart';
import 'package:meta_tool/commands/build/app/app_command.dart';
import 'package:meta_tool/commands/build/framework/framework_command.dart';
import 'package:meta_tool/commands/build/har/har_command.dart';
import 'package:meta_tool/commands/build/unity/base_unity_hot_asset_command.dart';
import 'package:meta_tool/commands/build/unity/export_first_package_command.dart';
import 'package:meta_tool/commands/build/unity/unity_cache_command.dart';
import 'package:meta_tool/commands/build/unity/unity_local_build_command.dart';
import 'package:meta_tool/commands/build/unity/unity_branch_build_command.dart';

class BuildCommand extends Command {
  @override
  String get description => '编译 Framework/aar/har/ipa/apk';

  @override
  String get name => 'build';

  BuildCommand() {
    addSubcommand(FrameworkCommand());
    addSubcommand(AarCommand());
    addSubcommand(HarCommand());
    addSubcommand(AppCommand());
    addSubcommand(UnityCacheCommand());
    addSubcommand(UnityHotAssetCommand());
    addSubcommand(UnityLocalBuildCommand());
    addSubcommand(UnityBranchBuildCommand());
    addSubcommand(ExportFirstPackageCommand());
  }
}
