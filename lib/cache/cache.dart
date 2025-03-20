import 'dart:io';

import 'package:meta_tool/cache/cache_manager.dart';
import 'package:meta_tool/cache/cache_model.dart';
import 'package:meta_tool/common.dart';
import 'package:path/path.dart';

typedef CacheFilter = bool Function(CacheModel data);

abstract class Cache {
  final String cacheHomeDir;
  final CacheManager cacheManager;
  Cache(this.cacheHomeDir, this.cacheManager);

  /// 过滤当前的缓存列表
  Future<List<CacheModel>> filterCacheDataList(CacheFilter filter) async {
    final models = await cacheManager.read();
    return models.where((e) => filter(e)).toList();
  }

  /// 获取最后的最新配置
  Future<CacheModel?> getLastCacheConfig([CacheFilter? filter]) async {
    final models = await filterCacheDataList(filter ?? (e) => true);
    if (models.isEmpty) return null;
    models.sort((a, b) {
      return b.commitTime.compareTo(a.commitTime);
    });
    return models.first;
  }

  /// 判断指定Commit Hash缓存是否存在
  Future<bool> isCacheExists(String commitHash) async {
    final cacheZipPath = getZipCachePath(commitHash);
    return File(cacheZipPath).exists();
  }

  String getZipCachePath(String commitHash) {
    return join(cacheHomeDir, '$commitHash.zip');
  }

  /// 更新指定分支的最新缓存Commit Hash
  Future<void> updateCacheData(File zipFile, CacheModel model) async {
    if (!Directory(cacheHomeDir).existsSync()) {
      await Directory(cacheHomeDir).create(recursive: true);
    }
    final cacheId = model.commitHash;
    final cacheZipPath = getZipCachePath(cacheId);
    await copyFile(zipFile, File(cacheZipPath));
    final infos = [...await cacheManager.read()];
    final index = infos.indexWhere((e) => e == model);
    if (index != -1) {
      infos[index] = model;
    } else {
      infos.add(model);
    }
    await cacheManager.write(infos);
  }
}
