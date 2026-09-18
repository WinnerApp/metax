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

  /// 判断指定 Commit Hash + 槽位的缓存 zip 是否存在。
  ///
  /// release 槽兼容旧路径 `{commit}.zip`。
  Future<bool> isCacheExists(
    String commitHash, {
    CacheArtifactKind artifactKind = CacheArtifactKind.release,
  }) async {
    return resolveExistingZipCachePath(
          commitHash,
          artifactKind: artifactKind,
        ) !=
        null;
  }

  /// 写入用的规范路径：`{commit}.{release|patched}.zip`
  String getZipCachePath(
    String commitHash, {
    CacheArtifactKind artifactKind = CacheArtifactKind.release,
  }) {
    return join(
      cacheHomeDir,
      '$commitHash.${artifactKind.name}.zip',
    );
  }

  /// 读取用：优先规范路径，release 槽回退旧 `{commit}.zip`。
  String? resolveExistingZipCachePath(
    String commitHash, {
    CacheArtifactKind artifactKind = CacheArtifactKind.release,
  }) {
    final preferred = getZipCachePath(commitHash, artifactKind: artifactKind);
    if (File(preferred).existsSync()) {
      return preferred;
    }
    if (artifactKind == CacheArtifactKind.release) {
      final legacy = join(cacheHomeDir, '$commitHash.zip');
      if (File(legacy).existsSync()) {
        return legacy;
      }
    }
    return null;
  }

  /// 更新指定分支的最新缓存 Commit Hash（按 [CacheModel.artifactKind] 分槽）。
  Future<void> updateCacheData(File zipFile, CacheModel model) async {
    if (!Directory(cacheHomeDir).existsSync()) {
      await Directory(cacheHomeDir).create(recursive: true);
    }
    final cacheZipPath = getZipCachePath(
      model.commitHash,
      artifactKind: model.artifactKind,
    );
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
