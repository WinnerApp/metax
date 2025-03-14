import 'dart:convert';
import 'dart:io';

import 'package:darty_json_safe/darty_json_safe.dart';
import 'package:meta_tool/cache/cache_model.dart';
import 'package:meta_tool/common.dart';
import 'package:path/path.dart';

abstract class CacheManager {
  final String cacheFilePath;
  const CacheManager(this.cacheFilePath);

  Future<List<CacheModel>> read() async {
    final jsonText =
        await File(cacheFilePath).readAsString().catchError((e) => '[]');
    final json = JSON(jsonText);
    return json.listValue.map((e) => CacheModel.fromJson(e)).toList();
  }

  Future<void> write(List<CacheModel> cacheModels) async {
    final jsonObject = cacheModels.map((e) => e.toJson()).toList();
    if (!await File(cacheFilePath).exists()) {
      await File(cacheFilePath).create(recursive: true);
    }
    final encoder = JsonEncoder.withIndent('  ');
    await File(cacheFilePath).writeAsString(encoder.convert(jsonObject));
  }

  /// 根据CommitHash获取缓存
  Future<CacheModel?> getCacheByCommitHash(String commitHash) async {
    final cacheModels = await read()
        .then((e) => e.where((e) => e.commitHash == commitHash).toList());
    if (cacheModels.isEmpty) {
      return null;
    }
    return cacheModels.first;
  }

  /// 追加缓存
  Future<void> appendCache(CacheModel cacheModel) async {
    final cacheModels = await read();
    cacheModels.add(cacheModel);
    await write(cacheModels);
  }
}

class BuildCacheManager extends CacheManager {
  final String buildCacheDir;
  BuildCacheManager(this.buildCacheDir)
      : super(join(buildCacheDir, 'cache.json'));
}

class MetaxCacheManager extends CacheManager {
  MetaxCacheManager()
      : super(join(join(readEnv('HOME'), '.metax'), 'cache.json'));
}
