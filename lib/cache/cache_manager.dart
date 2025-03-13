import 'dart:convert';
import 'dart:io';

import 'package:darty_json_safe/darty_json_safe.dart';
import 'package:meta_tool/cache/cache_model.dart';
import 'package:meta_tool/common.dart';
import 'package:meta_tool/define.dart';
import 'package:path/path.dart';

class CacheManager {
  final String cacheHome;
  final String cacheFileName;
  const CacheManager(this.cacheHome, this.cacheFileName);

  String get cacheJsonPath => join(cacheHome, cacheFileName);

  Future<List<CacheModel>> read() async {
    final jsonText =
        await File(cacheJsonPath).readAsString().catchError((e) => '[]');
    final json = JSON(jsonText);
    return json.listValue.map((e) => CacheModel.fromJson(e)).toList();
  }

  Future<void> write(List<CacheModel> cacheModels) async {
    final jsonObject = cacheModels.map((e) => e.toJson()).toList();
    if (!await File(cacheJsonPath).exists()) {
      await File(cacheJsonPath).create(recursive: true);
    }
    final encoder = JsonEncoder.withIndent('  ');
    await File(cacheJsonPath).writeAsString(encoder.convert(jsonObject));
  }

  /// 根据CommitHash获取缓存
  Future<CacheModel?> getCacheByCommitHash(String commitHash) async {
    final cacheModels = await read();
    return cacheModels.firstWhere((e) => e.commitHash == commitHash);
  }
}

class BuildCacheManager extends CacheManager {
  final String buildCacheDir;
  BuildCacheManager(this.buildCacheDir) : super(buildCacheDir, '.build_id');
}

class MetaxCacheManager extends CacheManager {
  final BuildPlatform buildPlatform;
  final bool isStore;
  final BuildConfiguration buildConfiguration;
  final BuildLibrary buildLibrary;
  final BuildType buildType;
  final String branch;
  final int buildId;
  MetaxCacheManager({
    required this.buildPlatform,
    required this.isStore,
    required this.buildConfiguration,
    required this.buildLibrary,
    required this.buildType,
    required this.branch,
    required this.buildId,
  }) : super(
          join(
            readEnv('HOME'),
            '.metax',
            buildPlatform.value,
            isStore ? 'store' : 'test',
            buildConfiguration.value,
            buildLibrary.value,
            buildType.value,
            branch,
            '$buildId',
          ),
          'cache.json',
        );
}
