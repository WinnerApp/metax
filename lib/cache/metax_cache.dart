import 'package:meta_tool/cache/cache.dart';
import 'package:meta_tool/cache/cache_manager.dart';
import 'package:meta_tool/cache/cache_model.dart';
import 'package:meta_tool/common.dart';
import 'package:meta_tool/define.dart';
import 'package:path/path.dart';

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
  }) : super(
          join(
            readEnv('HOME'),
            '.metax',
            buildPlatform.name,
            isStore ? 'store' : 'test',
            buildConfiguration.name,
            buildLibrary.name,
            buildType.name,
            branch,
            '$buildId',
          ),
          MetaxCacheManager(),
        );

  Future<String?> getCommitHashFromCacheId(String cacheId) async => cacheId;

  Future<CacheModel?> getCacheModelFromCacheId(String cacheId) async {
    final commitHash = await getCommitHashFromCacheId(cacheId);
    final models = await cacheManager.read().then((e) {
      return e
          .where((e) => e.buildPlatform == buildPlatform.name)
          .where((e) => e.buildLibrary == buildLibrary.name)
          .where((e) => e.buildType == buildType.name)
          .where((e) => e.branch == branch)
          .where((e) => e.buildId == buildId.toString())
          .where((e) => e.configuration == buildConfiguration.name)
          .where((e) => e.isStore == isStore)
          .where((e) => e.commitHash == commitHash)
          .toList();
    });
    return models.firstOrNull;
  }
}
