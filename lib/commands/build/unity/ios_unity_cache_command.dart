import 'package:meta_tool/commands/build/unity/base_unity_cache_command.dart';
import 'package:meta_tool/define.dart';

class IosUnityCacheCommand extends BaseUnityCacheCommand {
  @override
  String get description => '导出iOS unity 代码';

  @override
  String get name => 'ios';

  @override
  BuildPlatform get platform => BuildPlatform.ios;
}
