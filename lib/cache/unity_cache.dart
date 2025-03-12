import 'package:meta_tool/cache/metax_cache.dart';
import 'package:meta_tool/define.dart';

class UnityCache extends MetaxCache {
  UnityCache({
    required super.buildPlatform,
    required super.branch,
  }) : super(
          isStore: true,
          buildConfiguration: BuildConfiguration.release,
          buildLibrary: BuildLibrary.unity,
          buildType: BuildType.library,
        );
}
