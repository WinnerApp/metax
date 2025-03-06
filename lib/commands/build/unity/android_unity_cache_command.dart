import 'package:meta_tool/cache/unity_cache.dart';
import 'package:meta_tool/commands/build/unity/base_unity_cache_command.dart';

class AndroidUnityCacheCommand extends BaseUnityCacheCommand {
  @override
  String get description => '导出Android Unity代码';

  @override
  String get name => 'android';

  @override
  UnityCachePlatform get platform => UnityCachePlatform.android;
}
