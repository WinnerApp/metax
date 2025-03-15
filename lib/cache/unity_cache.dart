import 'package:meta_tool/cache/metax_cache.dart';
import 'package:meta_tool/define.dart';

class UnityCache extends MetaxCache {
  UnityCache({
    required super.buildPlatform,
    required super.branch,
    required super.buildId,
  }) : super(
          isStore: true,
          buildConfiguration: BuildConfiguration.release,
          buildLibrary: BuildLibrary.unity,
          buildType: BuildType.library,
        );

  @override
  Future<String?> getCommitHashFromCacheId(String cacheId) async {
    final models = await cacheManager.read().then((e) {
      return e
          .where((e) =>
              e.buildPlatform == buildPlatform.name &&
              e.isStore == isStore &&
              e.configuration == BuildConfiguration.release.name &&
              e.buildLibrary == BuildLibrary.unity.name &&
              e.buildType == BuildType.library.name &&
              e.branch == branch &&
              e.buildId == buildId.toString())
          .toList();
    });
    return models.isEmpty ? null : models.last.commitHash;
  }
}
