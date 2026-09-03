import 'package:args/command_runner.dart';
import 'package:meta_tool/commands/patch/patch_android_command.dart';
import 'package:meta_tool/commands/patch/patch_ios_command.dart';

class PatchCommand extends Command {
  @override
  String get name => 'patch';

  @override
  String get description => 'Shorebird 打补丁并推送到 Meta Code Push';

  PatchCommand() {
    addSubcommand(PatchIosCommand());
    addSubcommand(PatchAndroidCommand());
  }
}
