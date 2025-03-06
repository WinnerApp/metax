import 'dart:convert';
import 'dart:io';

import 'package:meta_tool/cache/cache.dart';
import 'package:path/path.dart';

class UnityCache extends Cache {
  final UnityCachePlatform platform;

  UnityCache({required this.platform}) : super();

  @override
  String get cacheHome => join(super.cacheHome, 'unity', platform.name);

  /// 获取指定分支最新的缓存Commit Hash
  Future<String?> getBranchLatestCommitHash(String branch) async {
    final cacheJsonPath = this.cacheJsonPath;
    if (!File(cacheJsonPath).existsSync()) {
      return null;
    }
    final cacheJson = jsonDecode(File(cacheJsonPath).readAsStringSync());
    return cacheJson[branch];
  }

  /// 判断指定Commit Hash缓存是否存在
  Future<bool> isCommitHashCacheExists(String commitHash) async {
    final cachePath = getCommitHashCachePath(commitHash);
    return File(cachePath).existsSync();
  }

  /// 获取指定Commit Hash缓存的路径
  String getCommitHashCachePath(String commitHash) {
    return join(cacheHome, '$commitHash.zip');
  }

  /// 更新指定分支的最新缓存Commit Hash
  Future<void> updateBranchLatestCommitHash(
      String branch, String commitHash) async {
    /// 删除之前的缓存
    final oldCacheCommitHash = await getBranchLatestCommitHash(branch);
    if (oldCacheCommitHash != null) {
      final oldCachePath = getCommitHashCachePath(oldCacheCommitHash);
      if (File(oldCachePath).existsSync()) {
        await File(oldCachePath).delete();
      }
    }

    final newCachePath = getCommitHashCachePath(commitHash);
    if (!File(newCachePath).existsSync()) {
      throw '缓存不存在';
    }

    /// 更新最新缓存
    final cacheJsonPath = this.cacheJsonPath;
    final cacheJsonText =
        await File(cacheJsonPath).readAsString().catchError((e) => '{}');
    final cacheJson = jsonDecode(cacheJsonText);
    cacheJson[branch] = commitHash;
    if (!await File(cacheJsonPath).exists()) {
      await File(cacheJsonPath).create(recursive: true);
    }
    await File(cacheJsonPath).writeAsString(jsonEncode(cacheJson));
  }
}

enum UnityCachePlatform {
  ios('ios'),
  android('android');

  final String name;

  const UnityCachePlatform(this.name);
}
