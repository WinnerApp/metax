import 'dart:async';

import 'package:meta_tool/cache/unity_cache.dart';
import 'package:meta_tool/commands/build/build_cache_command.dart';
import 'package:meta_tool/commands/unity_environment.dart';
import 'package:meta_tool/common.dart';
import 'package:meta_tool/define.dart';
import 'package:path/path.dart';
import 'package:process_runner/process_runner.dart';

abstract class BaseUnityCacheCommand extends BuildCacheCommand {
  BuildPlatform get platform;

  BaseUnityCacheCommand() {
    argParser.addFlag(
      'isUpload',
      help: '是否上传缓存,默认上传',
      defaultsTo: true,
    );
  }

  @override
  FutureOr? run() async {
    final isUpload = argResults?['isUpload'];
    final unityEnvironment = UnityEnvironment();
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
      workspaceDirectory = join(
        unityEnvironment.unityWorkspace,
        unityEnvironment.iosUnityPath,
      );
      appWorkspace = join(unityEnvironment.unityWorkspace, 'ios');
      unityCacheDir = join(appWorkspace, 'UnityLibrary');
    } else if (platform == BuildPlatform.android) {
      workspaceDirectory = join(
        unityEnvironment.unityWorkspace,
        unityEnvironment.androidUnityPath,
      );
      appWorkspace = join(unityEnvironment.unityWorkspace, 'android');
      unityCacheDir = join(appWorkspace, 'unityLibrary');
    }

    final branch = await getCurrentBranch(workspaceDirectory);
    final commitHash = await getCurrentCommitHash(workspaceDirectory);
    final commitTime = await getCommitTime(workspaceDirectory, commitHash);
    final unityCache = UnityCache(
      buildPlatform: platform,
      branch: branch,
    );

    await updateCache(
      cache: unityCache,
      commitHash: commitHash,
      buildCacheDir: unityCacheDir,
      commitTime: commitTime,
    );
    loggerSuccess('导出Unity代码完成');
    if (isUpload) {
      loggerDebug('上传缓存...');
      await uploadCacheResource(
        buildPlatform: platform,
        buildLibrary: BuildLibrary.unity,
        buildConfiguration: BuildConfiguration.release,
        buildType: BuildType.library,
        isStore: true,
        branch: branch,
        commitHash: commitHash,
      );
    }
  }

  @override
  Future<void> buildCache() async {
    await ProcessRunner().runProcess(
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
