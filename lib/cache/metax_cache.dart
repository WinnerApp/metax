import 'dart:io';

import 'package:meta_tool/cache/cache.dart';
import 'package:meta_tool/cache/cache_manager.dart';
import 'package:meta_tool/cache/cache_model.dart';
import 'package:meta_tool/common.dart';
import 'package:meta_tool/define.dart';
import 'package:path/path.dart';

class MetaxCache extends Cache {
  final BuildPlatform buildPlatform;
  final BuildConfiguration buildConfiguration;
  final BuildLibrary buildLibrary;
  final BuildType buildType;
  final String branch;
  final int buildId;
  MetaxCache({
    required this.buildPlatform,
    required this.buildConfiguration,
    required this.buildLibrary,
    required this.buildType,
    required this.branch,
    required this.buildId,
  }) : super(
          join(
            readEnv('HOME'),
            '.metax',
            buildPlatform.name,
            buildConfiguration.name,
            buildLibrary.name,
            buildType.name,
            branch,
            '$buildId',
          ),
          MetaxCacheManager(),
        );

  Future<String?> getCommitHashFromCacheId(String cacheId) async => cacheId;

  Future<CacheModel?> getCacheModelFromCacheId(
    String cacheId, {
    String flutterSdk = '',
  }) async {
    final commitHash = await getCommitHashFromCacheId(cacheId);
    final models = await cacheManager.read().then((e) {
      return e
          .where((e) => e.buildPlatform == buildPlatform.name)
          .where((e) => e.buildLibrary == buildLibrary.name)
          .where((e) => e.buildType == buildType.name)
          .where((e) => e.branch == branch)
          .where((e) => e.buildId == buildId.toString())
          .where((e) => e.configuration == buildConfiguration.name)
          .where((e) => e.commitHash == commitHash)
          .where((e) => e.flutterSdk == flutterSdk)
          .toList();
    });
    return models.firstOrNull;
  }

  /// 强制清理当前分支和构建ID的所有缓存
  Future<void> forceCleanCache() async {
    loggerDebug(
        '🧹 强制清理缓存: ${buildPlatform.name}/${buildLibrary.name}/${buildType.name}/$branch/$buildId');

    // 删除整个缓存目录（含 zip 与残留文件）
    final cacheDir = Directory(cacheHomeDir);
    if (await cacheDir.exists()) {
      await cacheDir.delete(recursive: true);
      loggerDebug('删除缓存目录: ${cacheDir.path}');
    }

    // 从全局缓存索引中移除相关条目
    final allModels = await cacheManager.read();
    final filteredModels = allModels.where((model) {
      return !(model.buildPlatform == buildPlatform.name &&
          model.buildLibrary == buildLibrary.name &&
          model.buildType == buildType.name &&
          model.branch == branch &&
          model.buildId == buildId.toString() &&
          model.configuration == buildConfiguration.name);
    }).toList();

    if (filteredModels.length != allModels.length) {
      await cacheManager.write(filteredModels);
      loggerDebug('已从缓存索引中移除 ${allModels.length - filteredModels.length} 个条目');
    }
  }
}
