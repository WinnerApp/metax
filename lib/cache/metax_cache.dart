import 'package:meta_tool/cache/cache.dart';
import 'package:meta_tool/cache/cache_manager.dart';
import 'package:meta_tool/define.dart';

class MetaxCache extends Cache {
  final BuildPlatform buildPlatform;
  final bool isStore;
  final BuildConfiguration buildConfiguration;
  final BuildLibrary buildLibrary;
  final BuildType buildType;
  final String branch;
  final int buildId;
  MetaxCache({
    required this.buildPlatform,
    required this.isStore,
    required this.buildConfiguration,
    required this.buildLibrary,
    required this.buildType,
    required this.branch,
    this.buildId = 0,
  }) : super(MetaxCacheManager(
          buildPlatform: buildPlatform,
          isStore: isStore,
          buildConfiguration: buildConfiguration,
          buildLibrary: buildLibrary,
          buildType: buildType,
          branch: branch,
          buildId: buildId,
        ));
}
