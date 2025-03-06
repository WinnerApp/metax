import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:meta_tool/cache/unity_cache.dart';
import 'package:meta_tool/common.dart';
import 'package:path/path.dart';
import 'package:process_runner/process_runner.dart';

abstract class BaseUnityCacheCommand extends Command {
  UnityCachePlatform get platform;

  @override
  FutureOr? run() async {
    final unityWorkspace = readEnv('UNITY_WORKSPACE');
    final iosUnityPath = readEnv('IOS_UNITY_PATH');
    final androidUnityPath = readEnv('ANDROID_UNITY_PATH');
    checkEnv('UNITY_ENGINE_PATH');
    if (!await isCommandInstall('build_winner_app')) {
      throw '请先通过dart pub global active build_winner_app 进行安装build_winner_app命令';
    }
    if (!await isCommandInstall('cmake')) {
      throw '请先通过brew install cmake 安装cmake';
    }

    late String workspaceDirectory;
    late String appWorkspace;
    late String unityCacheDir;
    if (platform == UnityCachePlatform.ios) {
      workspaceDirectory = join(unityWorkspace, iosUnityPath);
      appWorkspace = join(unityWorkspace, 'ios');
      unityCacheDir = join(appWorkspace, 'UnityLibrary');
    } else if (platform == UnityCachePlatform.android) {
      workspaceDirectory = join(unityWorkspace, androidUnityPath);
      appWorkspace = join(unityWorkspace, 'android');
      unityCacheDir = join(appWorkspace, 'unityLibrary');
    }

    final branch = await getCurrentBranch(workspaceDirectory);
    final commitHash = await getCurrentCommitHash(workspaceDirectory);
    final unityCache = UnityCache(platform: platform);
    final cacheZipPath = unityCache.getCommitHashCachePath(commitHash);
    final buildIdPath = join(unityCacheDir, '.build_id');
    String buildId = await File(buildIdPath)
        .readAsString()
        .then((value) => value.trim())
        .catchError((e) => '');
    if (await unityCache.isCommitHashCacheExists(commitHash) &&
        await File(cacheZipPath).exists()) {
      print('🔍 找到指定Commit Hash缓存，跳过导出Unity Framework代码');

      /// 删除现有导出
      await deleteDirIfExists(unityCacheDir);

      await copyFile(
        File(cacheZipPath),
        File(join(appWorkspace, 'UnityLibrary.zip')),
      );

      /// 解压zip
      await ProcessRunner().runProcess(
        [
          'unzip',
          "UnityLibrary.zip",
        ],
        workingDirectory: Directory(appWorkspace),
        printOutput: true,
      );

      /// 删除zip
      await File(join(appWorkspace, 'UnityLibrary.zip')).delete();
    } else if (buildId == commitHash) {
      print('🔍 当前Commit Hash与build_id.txt中的buildId一致，跳过导出Unity Framework代码');

      await writeToCacheSystem(
        appWorkspace: appWorkspace,
        commitHash: commitHash,
        cacheZipPath: cacheZipPath,
        branch: branch,
        unityCache: unityCache,
      );
    } else {
      await ProcessRunner().runProcess(
        [
          'build_winner_app',
          'export',
          '-p',
          platform.name,
        ],
        printOutput: true,
      );
      await createFileAndWrite(
        File(buildIdPath),
        commitHash,
      );
      await writeToCacheSystem(
        appWorkspace: appWorkspace,
        commitHash: commitHash,
        cacheZipPath: cacheZipPath,
        branch: branch,
        unityCache: unityCache,
      );
    }
    print('✅ 导出Unity Framework代码成功!');
  }

  /// 写入到缓存系统
  Future<void> writeToCacheSystem({
    required String appWorkspace,
    required String commitHash,
    required String cacheZipPath,
    required String branch,
    required UnityCache unityCache,
  }) async {
    /// 压缩
    await ProcessRunner().runProcess(
      [
        'zip',
        "-r",
        '$commitHash.zip',
        'UnityLibrary',
      ],
      workingDirectory: Directory(appWorkspace),
      printOutput: true,
    );

    final zipFile = File(join(appWorkspace, '$commitHash.zip'));

    await unityCache.updateBranchLatestCommitHash(branch, commitHash, zipFile);

    await zipFile.delete();

  }
}
