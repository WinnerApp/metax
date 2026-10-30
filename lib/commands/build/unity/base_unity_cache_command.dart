import 'dart:async';
import 'dart:io';

import 'package:meta_tool/argument_get.dart';
import 'package:meta_tool/cache/unity_cache.dart';
import 'package:meta_tool/commands/build/build_cache_command.dart';
import 'package:meta_tool/common.dart';
import 'package:meta_tool/define.dart';
import 'package:meta_tool/ohos_webgl_sync.dart';
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

    // 鸿蒙 WebGL：缓存落在 assets 后，再 sync 到 rawfile（注入 bridge）
    if (platform == BuildPlatform.ohos) {
      await syncOhosUnityWebglToRawfile(appHomeDir);
    }
  }

  @override
  Future<void> buildCache() async {
    final unityEnvironment = UnityEnvironment.fromEnvironment(appHomeDir);
    final skipExport =
        Platform.environment['METAX_SKIP_UNITY_EXPORT']?.toLowerCase() ==
            'true';
    if (skipExport && platform == BuildPlatform.ohos) {
      loggerWarning('METAX_SKIP_UNITY_EXPORT=true，跳过 Unity 批处理');
    } else {
      final appRunner = await createAppRunner(appHomeDir);
      // ohos → build_winner_app 调用 ExportAppData.exportOpenHarmony（Unity 引擎）
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
    }
    // Unity 导出后，把产物从 Unity 实际导出位置复制到 metax 期望的缓存目录
    await _copyExportedUnityToCacheDir(unityEnvironment);
  }

  /// 计算 metax 期望的 Unity 缓存目录（宿主工程内）
  String _getUnityCacheDir(UnityEnvironment unityEnvironment) {
    return switch (platform) {
      BuildPlatform.ios => join(appHomeDir.iosDir.path, 'UnityLibrary'),
      BuildPlatform.android => join(appHomeDir.androidDir.path, 'unityLibrary'),
      // 鸿蒙 WebGL 产物：ohos/unityWebgl/assets（再 sync 到 rawfile）
      BuildPlatform.ohos =>
        join(appHomeDir.ohosDir.path, 'unityWebgl', 'assets'),
    };
  }

  /// Unity 导出后，把产物从 Unity 实际导出位置复制到 metax 期望的缓存目录。
  ///
  /// Unity 侧导出路径为相对 Unity 工程真实路径的 ../../{platform}/unityLibrary
  /// （iOS 为 UnityLibrary）。Unity 工程外移（项目内软链共享）后，该相对路径
  /// 会解析到项目外（如 ~/Documents/{platform}/unityLibrary），与 metax 期望的
  /// 缓存目录不一致，需在此对齐。
  ///
  /// 鸿蒙 WebGL：`../../web/UnityLibrary` → `ohos/unityWebgl/assets` 再上传。
  Future<void> _copyExportedUnityToCacheDir(
      UnityEnvironment unityEnvironment) async {
    final workspaceDirectory =
        unityEnvironment.getPlatfromUnityWorkspace(platform.name);
    // Unity 的 Application.dataPath 返回真实路径（软链已解析），这里同样解析
    final realWorkspace =
        Directory(workspaceDirectory).resolveSymbolicLinksSync();
    final unityCacheDir = _getUnityCacheDir(unityEnvironment);
    final unityExportDir = _resolveUnityExportDir(realWorkspace);

    if (normalize(unityExportDir) == normalize(unityCacheDir)) {
      return;
    }
    if (!Directory(unityExportDir).existsSync()) {
      throw Exception('Unity 导出目录不存在: $unityExportDir');
    }
    loggerInfo('📦 复制 Unity 导出产物: $unityExportDir -> $unityCacheDir');
    await copyDirToDir(Directory(unityExportDir), Directory(unityCacheDir));
  }

  String _resolveUnityExportDir(String realWorkspace) {
    if (platform == BuildPlatform.ios) {
      return normalize(join(realWorkspace, '../../ios/UnityLibrary'));
    }
    if (platform == BuildPlatform.ohos) {
      final candidates = [
        normalize(join(realWorkspace, '../../web/UnityLibrary')),
        normalize(join(realWorkspace, '../../web/unityLibrary')),
      ];
      for (final path in candidates) {
        if (Directory(path).existsSync()) {
          return path;
        }
      }
      throw Exception(
        '鸿蒙 WebGL 导出目录不存在，已检查: ${candidates.join(', ')}',
      );
    }
    return normalize(
      join(realWorkspace, '../../${platform.name}/unityLibrary'),
    );
  }
}
