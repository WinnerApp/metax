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
  Future<void> updateCache({
    required MetaxCache cache,
    required String commitHash,
    required String buildCacheDir,
  }) async {
    final cacheCommitHash = await cache.getLastCacheCommitHash();
    final startTime = DateTime.now();
    final buildModel = CacheModel(
      buildPlatform: cache.buildPlatform.value,
      buildLibrary: cache.buildLibrary.value,
      buildType: cache.buildType.value,
      branch: cache.branch,
      configuration: cache.buildConfiguration.value,
      commitHash: commitHash,
      buildId: cache.buildId.toString(),
      isStore: cache.isStore,
    );
    if (cacheCommitHash != null && await cache.isCacheExists(commitHash)) {
      loggerWarning('🔍 本地缓存目录存在指定缓存，跳过编译......');
    } else if (await isCacheExitsInBuildDir(buildModel, buildCacheDir)) {
      loggerInfo('🔍 当前编译已经是最新的,正在复制到本地缓存目录......');

      await writeToCacheSystem(
        buildCacheDir: buildCacheDir,
        cache: cache,
        commitHash: commitHash,
      );
    } else {
      // await deleteDirIfExists(buildCacheDir);
      await buildCache();
      await BuildCacheManager(buildCacheDir).write([
        CacheModel(
          buildPlatform: cache.buildPlatform.value,
          buildLibrary: cache.buildLibrary.value,
          buildType: cache.buildType.value,
          branch: cache.branch,
          configuration: cache.buildConfiguration.value,
          commitHash: commitHash,
          buildId: cache.buildId.toString(),
          isStore: cache.isStore,
        ),
      ]);
      await writeToCacheSystem(
        buildCacheDir: buildCacheDir,
        cache: cache,
        commitHash: commitHash,
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
  }) async {
    final buildCacheParentDir = Directory(buildCacheDir).parent;
    final cacheBaseName = basename(buildCacheDir);

    String cacheId = commitHash;

    /// 压缩
    await ProcessRunner().runProcess(
      [
        'zip',
        "-r",
        '$cacheId.zip',
        cacheBaseName,
      ],
      workingDirectory: buildCacheParentDir,
      printOutput: true,
    );

    final zipFile = File(join(buildCacheParentDir.path, '$cacheId.zip'));
    await cache.updateCacheData(
      zipFile,
      CacheModel(
        branch: cache.branch,
        commitHash: commitHash,
        buildId: cache.buildId.toString(),
        isStore: cache.isStore,
        configuration: cache.buildConfiguration.value,
        buildPlatform: cache.buildPlatform.value,
        buildLibrary: cache.buildLibrary.value,
        buildType: cache.buildType.value,
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
