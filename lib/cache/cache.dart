import 'dart:convert';
import 'dart:io';

import 'package:meta_tool/common.dart';
import 'package:path/path.dart';

abstract class Cache {
  String get cacheHome => join(readEnv('HOME'), '.metax');
  String get cacheJsonPath => join(cacheHome, 'cache.json');

  /// 获取指定分支最新的缓存Commit Hash
  Future<String?> getBranchLatestCommitHash(String branch);

  Future<Map<String, dynamic>> getCacheData(String branch) async {
    final jsonText =
        await File(cacheJsonPath).readAsString().catchError((e) => '{}');
    return jsonDecode(jsonText);
  }

  /// 判断指定Commit Hash缓存是否存在
  Future<bool> isCommitHashCacheExists(String commitHash) async {
    return await File(getCommitHashCachePath(commitHash)).exists();
  }

  String getCommitHashCachePath(String commitHash) {
    return join(cacheHome, '$commitHash.zip');
  }

  /// 更新指定分支的最新缓存Commit Hash
  Future<void> updateBranchLatestCommitHash(
      String branch, String commitHash, File zipFile) async {
    final cacheZipPath = getCommitHashCachePath(commitHash);
    await copyFile(zipFile, File(cacheZipPath));
    final jsonText =
        await File(cacheJsonPath).readAsString().catchError((e) => '{}');
    final data = updateCacheData(jsonDecode(jsonText), branch, commitHash);
    if (!await File(cacheJsonPath).exists()) {
      await File(cacheJsonPath).create(recursive: true);
    }
    await File(cacheJsonPath).writeAsString(jsonEncode(data));
  }

  Map<String, dynamic> updateCacheData(
      Map<String, dynamic> cacheData, String branch, String commitHash);
}
