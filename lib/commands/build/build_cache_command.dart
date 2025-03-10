import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:darty_json_safe/darty_json_safe.dart';
import 'package:meta_tool/cache/cache.dart';
import 'package:meta_tool/common.dart';
import 'package:path/path.dart';
import 'package:process_runner/process_runner.dart';

abstract class BuildCacheCommand extends Command {
  Future<void> updateCache({
    required Cache cache,
    required String branch,
    required String commitHash,
    required String buildCacheDir,
    Map<String, dynamic>? data,
  }) async {
    final buildIdPath = join(buildCacheDir, '.build_id');
    final buildId = await getBuildIdFromFile(File(buildIdPath));
    final startTime = DateTime.now();
    if (await cache.isCommitHashCacheExists(commitHash)) {
      loggerWarning('🔍 本地存在指定$commitHash缓存，跳过编译......');
    } else if (buildId == commitHash) {
      loggerInfo('🔍 当前编译已经是最新的,正在复制到本地缓存目录......');

      await writeToCacheSystem(
        buildCacheDir: buildCacheDir,
        commitHash: commitHash,
        branch: branch,
        cache: cache,
      );
    } else {
      await deleteDirIfExists(buildCacheDir);
      await buildCache();
      final content = json.encode({'branch': branch, 'commitHash': commitHash});
      await createFileAndWrite(File(buildIdPath), content);
      await writeToCacheSystem(
        buildCacheDir: buildCacheDir,
        commitHash: commitHash,
        branch: branch,
        cache: cache,
      );
    }
    final endTime = DateTime.now();
    loggerInfo('🔍 编译完成，用时: ${endTime.difference(startTime).inSeconds}秒');
  }

  /// 写入到缓存系统
  Future<void> writeToCacheSystem({
    required String buildCacheDir,
    required String commitHash,
    required String branch,
    required Cache cache,
    Map<String, dynamic>? data,
  }) async {
    final buildCacheParentDir = Directory(buildCacheDir).parent;
    final cacheBaseName = basename(buildCacheDir);

    /// 压缩
    await ProcessRunner().runProcess(
      [
        'zip',
        "-r",
        '$commitHash.zip',
        cacheBaseName,
      ],
      workingDirectory: buildCacheParentDir,
      printOutput: true,
    );

    final zipFile = File(join(buildCacheParentDir.path, '$commitHash.zip'));
    await cache.updateBranchLatestCommitHash(
      branch,
      commitHash,
      zipFile,
      data,
    );
    await zipFile.delete();
  }

  Future<void> buildCache() async {}

  Future<String?> getBuildIdFromFile(File file) async {
    final content = await file.readAsString().catchError((e) => '{}');
    final json = JSON(content);
    final commitHash = json['commitHash'].string;
    return commitHash;
  }
}
