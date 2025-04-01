import 'dart:async';

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
        );
      }
    }
  }

  @override
  Future<void> buildCache() async {
    final appRunner = await createAppRunner(appHomeDir);
    await appRunner.runProcess(
      [
        'build_winner_app',
        'export',
        '-p',
        platform.name,
      ],
      printOutput: true,
    );
  }
}
