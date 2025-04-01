import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:meta_tool/cache/build_cache.dart';
import 'package:meta_tool/cache/cache_manager.dart';
import 'package:meta_tool/cache/cache_model.dart';
import 'package:meta_tool/cache/metax_cache.dart';
import 'package:meta_tool/common.dart';
import 'package:path/path.dart';
import 'package:process_runner/process_runner.dart';

abstract class BuildCacheCommand extends Command {
  BuildCacheCommand() {
    argParser.addFlag(
      'isUpload',
      help: '是否上传缓存',
      defaultsTo: true,
    );
  }

  late bool isUpload;

  @override
  FutureOr? run() async {
    isUpload = argResults?['isUpload'] ?? true;
  }

  Future<void> updateCache({
    required MetaxCache cache,
    required String commitHash,
    required String buildCacheDir,
    required DateTime commitTime,
    required String cacheId,
    bool forceUpdate = false,
  }) async {
    final cacheModel = await cache.getCacheModelFromCacheId(cacheId);
    final startTime = DateTime.now();
    final buildModel = CacheModel(
      buildPlatform: cache.buildPlatform.value,
      buildLibrary: cache.buildLibrary.value,
      buildType: cache.buildType.value,
      branch: cache.branch,
      configuration: cache.buildConfiguration.value,
      commitHash: commitHash,
      buildId: cache.buildId.toString(),
      commitTime: commitTime,
      isStore: false,
    );

    if (cacheModel != null &&
        await cache.isCacheExists(cacheModel.commitHash) &&
        !forceUpdate) {
      loggerWarning('🔍 本地缓存目录存在指定缓存，跳过编译......');
      commitHash = cacheModel.commitHash;
    } else if (await isCacheExitsInBuildDir(buildModel, buildCacheDir) &&
        !forceUpdate) {
      loggerInfo('🔍 当前编译已经是最新的,正在复制到本地缓存目录......');

      await writeToCacheSystem(
        buildCacheDir: buildCacheDir,
        cache: cache,
        commitHash: commitHash,
        commitTime: commitTime,
      );
    } else {
      await buildCache();
      if (!Directory(buildCacheDir).existsSync()) {
        throw Exception('编译缓存目录不存在: $buildCacheDir');
      }
      await BuildCacheManager(buildCacheDir).write([
        CacheModel(
          buildPlatform: cache.buildPlatform.value,
          buildLibrary: cache.buildLibrary.value,
          buildType: cache.buildType.value,
          branch: cache.branch,
          configuration: cache.buildConfiguration.value,
          commitHash: commitHash,
          buildId: cache.buildId.toString(),
          isStore: false,
          commitTime: commitTime,
        ),
      ]);
      await writeToCacheSystem(
        buildCacheDir: buildCacheDir,
        cache: cache,
        commitHash: commitHash,
        commitTime: commitTime,
      );
    }
    final endTime = DateTime.now();
    loggerInfo('🔍 编译完成，用时: ${endTime.difference(startTime).inSeconds}秒');
  }

  /// 写入到缓存系统
  Future<void> writeToCacheSystem({
    required String buildCacheDir,
    required MetaxCache cache,
    required String commitHash,
    required DateTime commitTime,
  }) async {
    final buildCacheParentDir = Directory(buildCacheDir).parent;
    // final cacheBaseName = basename(buildCacheDir);

    String cacheId = commitHash;

    /// 压缩
    await ProcessRunner().runProcess(
      [
        'zip',
        "-r",
        join(buildCacheParentDir.path, '$cacheId.zip'),
        './',
      ],
      workingDirectory: Directory(buildCacheDir),
      printOutput: true,
    );

    final zipFile = File(join(buildCacheParentDir.path, '$cacheId.zip'));
    await cache.updateCacheData(
      zipFile,
      CacheModel(
        branch: cache.branch,
        commitHash: commitHash,
        buildId: cache.buildId.toString(),
        configuration: cache.buildConfiguration.value,
        buildPlatform: cache.buildPlatform.value,
        buildLibrary: cache.buildLibrary.value,
        buildType: cache.buildType.value,
        commitTime: commitTime,
        isStore: false,
      ),
    );
    await zipFile.delete();
  }

  Future<void> buildCache() async {}

  /// 当前编译目录是否存在缓存文件
  Future<bool> isCacheExitsInBuildDir(
      CacheModel buildModel, String buildCacheDir) async {
    final buildCache = BuildCache(buildCacheDir);
    final lastBuildConfig = await buildCache.getLastCacheConfig();
    if (lastBuildConfig == null) return false;
    return buildModel == lastBuildConfig;
  }
}
