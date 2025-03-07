import 'package:meta_tool/commands/build/unity/base_unity_cache_command.dart';
import 'package:meta_tool/define.dart';

class AndroidUnityCacheCommand extends BaseUnityCacheCommand {
  @override
  String get description => '导出Android Unity代码';

  @override
  String get name => 'android';

  @override
  BuildPlatform get platform => BuildPlatform.android;
}
