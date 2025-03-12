import 'dart:io';
import 'package:meta_tool/cache/cache_manager.dart';
import 'package:meta_tool/cache/cache_model.dart';
import 'package:meta_tool/common.dart';
import 'package:path/path.dart';

typedef CacheFilter = bool Function(CacheModel data);

abstract class Cache {
  final CacheManager cacheManager;
  Cache(this.cacheManager);

  /// 过滤当前的缓存列表
  Future<List<CacheModel>> filterCacheDataList(CacheFilter filter) async {
    final models = await cacheManager.read();
    return models.where((e) => filter(e)).toList();
  }

  /// 获取最后的最新配置
  Future<CacheModel?> getLastCacheConfig([CacheFilter? filter]) async {
    final models = await filterCacheDataList(filter ?? (e) => true);
    if (models.isEmpty) return null;
    return models.last;
  }

  /// 根据cacheId获取缓存Commit Hash
  Future<String?> getLastCacheCommitHash([CacheFilter? filter]) async {
    final config = await getLastCacheConfig(filter);
    return config?.commitHash;
  }

  /// 判断指定Commit Hash缓存是否存在
  Future<bool> isCacheExists(String commitHash) async {
    return getZipCachePath(commitHash)
        .then((e) => File(e).exists())
        .catchError((e) => false);
  }

  Future<String> getZipCachePath(String commitHash) async {
    return join(cacheManager.cacheHome, '$commitHash.zip');
  }

  /// 更新指定分支的最新缓存Commit Hash
  Future<void> updateCacheData(File zipFile, CacheModel model) async {
    final cacheId = model.buildId;
    final cacheZipPath = await getZipCachePath(cacheId);
    await copyFile(zipFile, File(cacheZipPath));
    final infos = [...await cacheManager.read()];
    final index = infos.indexWhere((e) => e.commitHash == model.commitHash);
    if (index != -1) {
      infos[index] = model;
    } else {
      infos.add(model);
    }
    await cacheManager.write(infos);
  }
}
