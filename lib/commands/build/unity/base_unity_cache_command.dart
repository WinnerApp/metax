import 'dart:async';
import 'dart:io';

import 'package:meta_tool/argument_get.dart';
import 'package:meta_tool/cache/unity_cache.dart';
import 'package:meta_tool/commands/build/build_cache_command.dart';
import 'package:meta_tool/common.dart';
import 'package:meta_tool/define.dart';
import 'package:meta_tool/unity_environment.dart';
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
    if (!await isCommandInstall('build_winner_app')) {
      throw '请先通过dart pub global activate build_winner_app 进行安装build_winner_app命令';
    }
    if (!await isCommandInstall('cmake')) {
      throw '请先通过brew install cmake 安装cmake';
    }

    final workspaceDirectory =
        unityEnvironment.getPlatfromUnityWorkspace(platform.name);
    final unityCacheDir = _getUnityCacheDir(unityEnvironment);

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
      } else if (platform == BuildPlatform.ohos) {
        await copyDirToDir(
          MockType.ohosUnityLibrary.mockDir(appHomeDir),
          MockType.ohosUnityLibrary.sourceCacheDir(appHomeDir),
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
    final appRunner = await createAppRunner(appHomeDir);
    await appRunner.runProcess(
      [
        'build_winner_app',
        'export',
        '-p',
        platform.name,
        '-u',
        unityEnvironment.getEnginePath(platform.name),
      ],
      printOutput: true,
    );
    // Unity 导出后，把产物从 Unity 实际导出位置复制到 metax 期望的缓存目录
    await _copyExportedUnityToCacheDir(unityEnvironment);
  }

  /// 计算 metax 期望的 Unity 缓存目录
  String _getUnityCacheDir(UnityEnvironment unityEnvironment) {
    final appWorkspace = join(unityEnvironment.unityWorkspace, platform.name);
    return switch (platform) {
      BuildPlatform.ios => join(appWorkspace, 'UnityLibrary'),
      BuildPlatform.android => join(appWorkspace, 'unityLibrary'),
      BuildPlatform.ohos => join(appWorkspace, 'unityLibrary'),
    };
  }

  /// Unity 导出后，把产物从 Unity 实际导出位置复制到 metax 期望的缓存目录。
  ///
  /// Unity 侧导出路径为相对 Unity 工程真实路径的 ../../{platform}/unityLibrary
  /// （iOS 为 UnityLibrary）。Unity 工程外移（项目内软链共享）后，该相对路径
  /// 会解析到项目外（如 ~/Documents/{platform}/unityLibrary），与 metax 期望的
  /// 缓存目录不一致，需在此对齐。
  Future<void> _copyExportedUnityToCacheDir(
      UnityEnvironment unityEnvironment) async {
    final workspaceDirectory =
        unityEnvironment.getPlatfromUnityWorkspace(platform.name);
    // Unity 的 Application.dataPath 返回真实路径（软链已解析），这里同样解析
    final realWorkspace =
        Directory(workspaceDirectory).resolveSymbolicLinksSync();
    final exportRelativePath = platform == BuildPlatform.ios
        ? '../../ios/UnityLibrary'
        : '../../${platform.name}/unityLibrary';
    final unityExportDir = normalize(join(realWorkspace, exportRelativePath));
    final unityCacheDir = _getUnityCacheDir(unityEnvironment);

    if (normalize(unityExportDir) == normalize(unityCacheDir)) {
      return;
    }
    if (!Directory(unityExportDir).existsSync()) {
      throw Exception('Unity 导出目录不存在: $unityExportDir');
    }
    loggerInfo('📦 复制 Unity 导出产物: $unityExportDir -> $unityCacheDir');
    await copyDirToDir(Directory(unityExportDir), Directory(unityCacheDir));
  }
}
