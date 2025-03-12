import 'dart:async';
import 'package:meta_tool/cache/unity_cache.dart';
import 'package:meta_tool/commands/build/build_cache_command.dart';
import 'package:meta_tool/common.dart';
import 'package:meta_tool/define.dart';
import 'package:path/path.dart';
import 'package:process_runner/process_runner.dart';

abstract class BaseUnityCacheCommand extends BuildCacheCommand {
  BuildPlatform get platform;

  @override
  FutureOr? run() async {
    final unityWorkspace = readEnv('UNITY_WORKSPACE');
    final iosUnityPath = readEnv('IOS_UNITY_PATH');
    final androidUnityPath = readEnv('ANDROID_UNITY_PATH');
    checkEnv('UNITY_ENGINE_PATH');
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
      workspaceDirectory = join(unityWorkspace, iosUnityPath);
      appWorkspace = join(unityWorkspace, 'ios');
      unityCacheDir = join(appWorkspace, 'UnityLibrary');
    } else if (platform == BuildPlatform.android) {
      workspaceDirectory = join(unityWorkspace, androidUnityPath);
      appWorkspace = join(unityWorkspace, 'android');
      unityCacheDir = join(appWorkspace, 'unityLibrary');
    }

    final branch = await getCurrentBranch(workspaceDirectory);
    final commitHash = await getCurrentCommitHash(workspaceDirectory);

    final unityCache = UnityCache(
      buildPlatform: platform,
      branch: branch,
    );

    await updateCache(
      cache: unityCache,
      commitHash: commitHash,
      buildCacheDir: unityCacheDir,
    );
    loggerSuccess('导出Unity代码完成');
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
