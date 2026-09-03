import 'package:meta_tool/commands/patch/base_patch_command.dart';

class PatchAndroidCommand extends BasePatchCommand {
  @override
  String get name => 'android';

  @override
  String get description => 'Android Shorebird 补丁并推送 Meta OTA';

  @override
  String get otaPlatform => 'android';

  @override
  String get shorebirdPlatform => 'aar';
}
