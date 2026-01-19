import 'dart:async';
import 'dart:io';

import 'package:meta_tool/argument_get.dart';
import 'package:meta_tool/cache/unity_cache.dart';
import 'package:meta_tool/commands/build/build_cache_command.dart';
import 'package:meta_tool/common.dart';
import 'package:meta_tool/define.dart';
import 'package:meta_tool/unity_environment.dart';
import 'package:meta_tool/update_unity.dart';
import 'package:path/path.dart';

abstract class BaseUnityCacheCommand extends BuildCacheCommand {
  BaseUnityCacheCommand() {
    argParser.addOption(
      'unityBranch',
      help: 'Unity分支',
    );
  }

  BuildPlatform get platform;
  @override
  FutureOr? run() async {
    await super.run();
    final unityEnvironment = UnityEnvironment.fromEnvironment(appHomeDir);
    if (!await isCommandInstall('cmake')) {
      throw '请先通过brew install cmake 安装cmake';
    }

    late String workspaceDirectory;
    late String appWorkspace;
    late String unityCacheDir;
    if (platform == BuildPlatform.ios) {
      workspaceDirectory = unityEnvironment.iosUnityWorkspace;
      appWorkspace = join(unityEnvironment.unityWorkspace, 'ios');
      unityCacheDir = join(appWorkspace, 'UnityLibrary');
    } else if (platform == BuildPlatform.android) {
      workspaceDirectory = unityEnvironment.androidUnityWorkspace;
      appWorkspace = join(unityEnvironment.unityWorkspace, 'android');
      unityCacheDir = join(appWorkspace, 'unityLibrary');
    }

    if (useMock) {
      if (platform == BuildPlatform.ios) {
        await copyDirToDir(
          MockType.iosUnityLibrary.mockDir(appHomeDir),
          MockType.iosUnityLibrary.sourceCacheDir(appHomeDir),
        );
      } else if (platform == BuildPlatform.android) {
        await copyDirToDir(
          MockType.androidUnityLibrary.mockDir(appHomeDir),
          MockType.androidUnityLibrary.sourceCacheDir(appHomeDir),
        );
      }
      loggerSuccess('导出Unity代码完成');
    } else {
      /// 如果开启skipGitPull，则跳过Git操作，直接使用本地代码
      if (skipGitPull) {
        loggerInfo('跳过Git操作模式，使用本地代码');
        final branch = await getCurrentBranch(workspaceDirectory);
        final commitHash = await getCurrentCommitHash(workspaceDirectory);
        final commitTime = await getCommitTime(workspaceDirectory, commitHash);
        final buildId = await getUnityBuildVersion(workspaceDirectory);
        final unityCache = UnityCache(
          buildPlatform: platform,
          branch: branch,
          buildId: buildId,
        );

        await updateCache(
          cache: unityCache,
          commitHash: commitHash,
          buildCacheDir: unityCacheDir,
          commitTime: commitTime,
          cacheId: buildId.toString(),
          forceUpdate: forceUpdate,
        );
        loggerSuccess('导出Unity代码完成');
        if (isUpload) {
          loggerDebug('上传缓存...');
          await uploadCacheResource(
            buildPlatform: platform,
            buildLibrary: BuildLibrary.unity,
            buildConfiguration: BuildConfiguration.release,
            buildType: BuildType.library,
            branch: branch,
            commitHash: commitHash,
            commitTime: commitTime,
            buildId: buildId,
          );
        }
      } else {
        /// 当前分支列表
        final branchList = await getLatestBranchList(workspaceDirectory);
        final chooseBranch = ArgumentGet(argResults).getString(
          'unityBranch',
          '请选择Unity分支',
          allowed: branchList,
        );
        await switchBranch(workspaceDirectory, chooseBranch);
        final branch = await getCurrentBranch(workspaceDirectory);
        final commitHash = await getCurrentCommitHash(workspaceDirectory);
        final commitTime = await getCommitTime(workspaceDirectory, commitHash);
        final buildId = await getUnityBuildVersion(workspaceDirectory);
        final unityCache = UnityCache(
          buildPlatform: platform,
          branch: branch,
          buildId: buildId,
        );

        await updateCache(
          cache: unityCache,
          commitHash: commitHash,
          buildCacheDir: unityCacheDir,
          commitTime: commitTime,
          cacheId: buildId.toString(),
          forceUpdate: forceUpdate,
        );
        loggerSuccess('导出Unity代码完成');
        if (isUpload) {
          loggerDebug('上传缓存...');
          await uploadCacheResource(
            buildPlatform: platform,
            buildLibrary: BuildLibrary.unity,
            buildConfiguration: BuildConfiguration.release,
            buildType: BuildType.library,
            branch: branch,
            commitHash: commitHash,
            commitTime: commitTime,
            buildId: buildId,
          );
        }
      }
    }
  }

  @override
  Future<void> buildCache() async {
    final unityEnvironment = UnityEnvironment.fromEnvironment(appHomeDir);

    // 确定 Unity 工作空间和平台
    late String workspace;
    late UnityPlatform unityPlatform;
    if (platform == BuildPlatform.ios) {
      workspace = unityEnvironment.iosUnityWorkspace;
      unityPlatform = UnityPlatform.ios;
    } else if (platform == BuildPlatform.android) {
      workspace = unityEnvironment.androidUnityWorkspace;
      unityPlatform = UnityPlatform.android;
    } else {
      throw Exception('不支持的平台: ${platform.name}');
    }

    // 使用 UpdateUnity 类直接导出 Unity 缓存
    final updateUnity = UpdateUnity(
      workspace: workspace,
      unityEnginePath: unityEnvironment.unityEnginePath,
      platform: unityPlatform,
    );

    final success = await updateUnity.update();
    if (!success) {
      exit(1);
    }
  }
}
