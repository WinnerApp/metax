import 'package:meta_tool/commands/patch/base_patch_command.dart';

class PatchIosCommand extends BasePatchCommand {
  @override
  String get name => 'ios';

  @override
  String get description => 'iOS Shorebird 补丁并推送 Meta OTA';

  @override
  String get otaPlatform => 'ios';

  @override
  String get shorebirdPlatform => 'ios-framework';
}
