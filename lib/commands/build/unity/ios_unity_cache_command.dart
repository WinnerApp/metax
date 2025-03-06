import 'package:meta_tool/cache/unity_cache.dart';
import 'package:meta_tool/commands/build/unity/base_unity_cache_command.dart';

class IosUnityCacheCommand extends BaseUnityCacheCommand {
  @override
  String get description => '导出iOS unity 代码';

  @override
  String get name => 'ios';

  @override
  UnityCachePlatform get platform => UnityCachePlatform.ios;
}
