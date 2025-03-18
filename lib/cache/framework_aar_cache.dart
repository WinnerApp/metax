import 'package:meta_tool/cache/metax_cache.dart';
import 'package:meta_tool/define.dart';

class FrameworkCache extends MetaxCache {
  FrameworkCache({
    required super.isStore,
    required super.branch,
    required super.buildConfiguration,
    required super.buildLibrary,
  }) : super(buildType: BuildType.framework, buildPlatform: BuildPlatform.ios);
}

class AarCache extends MetaxCache {
  AarCache({
    required super.isStore,
    required super.branch,
    required super.buildConfiguration,
    required super.buildLibrary,
  }) : super(buildType: BuildType.aar, buildPlatform: BuildPlatform.android);
}
