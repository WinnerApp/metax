import 'package:meta_tool/commands/build/unity/base_unity_cache_command.dart';
import 'package:meta_tool/define.dart';

class OhosUnityCacheCommand extends BaseUnityCacheCommand {
  @override
  String get description => '导出鸿蒙 Unity/团结 Library 代码';

  @override
  String get name => 'ohos';

  @override
  BuildPlatform get platform => BuildPlatform.ohos;
}
