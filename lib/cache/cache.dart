import 'dart:convert';
import 'dart:io';
import 'package:darty_json_safe/darty_json_safe.dart';
import 'package:meta_tool/common.dart';
import 'package:path/path.dart';

typedef CacheFilter = Map<String, dynamic>? Function(Map<String, dynamic> data);

abstract class Cache {
  String get cacheHome;
  String get cacheJsonPath;

  Future<List<Map<String, dynamic>>> filterCacheDataList(
      [CacheFilter? filter]) async {
    final infos = await getCacheDataList();
    return infos
        .map((e) => filter?.call(e) ?? e)
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  /// 判断指定Commit Hash缓存是否存在
  Future<bool> isCommitHashCacheExists(String commitHash) async {
    return await File(getCommitHashCachePath(commitHash)).exists();
  }

  String getCommitHashCachePath(String commitHash) {
    return join(cacheHome, '$commitHash.zip');
  }

  /// 更新指定分支的最新缓存Commit Hash
  Future<void> updateCacheData(File zipFile, Map<String, dynamic> data) async {
    final commitHash = data['commitHash'];
    final cacheZipPath = getCommitHashCachePath(commitHash);
    await copyFile(zipFile, File(cacheZipPath));
    final infos = [...await getCacheDataList()];
    infos.add(data);
    if (!await File(cacheJsonPath).exists()) {
      await File(cacheJsonPath).create(recursive: true);
    }
    await File(cacheJsonPath).writeAsString(jsonEncode(infos));
  }

  Future<List<Map<String, dynamic>>> getCacheDataList() async {
    final jsonText =
        await File(cacheJsonPath).readAsString().catchError((e) => '[]');
    final json = JSON(jsonText);
    return json.listValue.map((e) {
      if (e is Map) {
        return e.map((key, value) => MapEntry(key.toString(), value));
      }
      return <String, dynamic>{};
    }).toList();
  }
}
