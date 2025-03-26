import 'dart:io';

import 'package:meta_tool/cache/cache_manager.dart';
import 'package:meta_tool/cache/framework_aar_cache.dart';
import 'package:meta_tool/commands/build/build_cache_command.dart';
import 'package:meta_tool/common.dart';
import 'package:meta_tool/define.dart';
import 'package:path/path.dart';
import 'package:process_runner/process_runner.dart';

class UnityAarCommand extends BuildCacheCommand {
  @override
  String get description => '打包unity aar';

  @override
  String get name => 'unity';

  @override
  Future<void> run() async {
    await super.run();
    final unityDir = Directory(join(
      appHomeDir.androidDir.path,
      'unityLibrary',
    ));
    if (!unityDir.existsSync()) {
      throw Exception('unityLibrary目录不存在: ${unityDir.path}');
    }
    final cacheManager = BuildCacheManager(unityDir.path);
    final models = await cacheManager.read();
    final cache = models.first;
    final branch = cache.branch;
    final commitHash = cache.commitHash;
    final commitTime = cache.commitTime;
    final unityCache = AarCache(
      isStore: true,
      branch: branch,
      buildConfiguration: BuildConfiguration.release,
      buildLibrary: BuildLibrary.unity,
    );
    final buildCacheDir = join(
      appHomeDir.workspace,
      'build',
      'unityLibrary',
      'outputs',
      'aar',
    );
    await updateCache(
      cache: unityCache,
      commitHash: commitHash,
      buildCacheDir: buildCacheDir,
      commitTime: commitTime,
      cacheId: cache.buildId.toString(),
    );

    loggerSuccess('打包Unity AAR完成!');
    if (isUpload) {
      loggerDebug('上传缓存...');
      await uploadCacheResource(
        buildPlatform: BuildPlatform.android,
        buildLibrary: BuildLibrary.unity,
        buildConfiguration: BuildConfiguration.release,
        buildType: BuildType.aar,
        isStore: true,
        branch: branch,
        commitHash: commitHash,
        commitTime: commitTime,
      );
    }
  }

  @override
  Future<void> buildCache() async {
    final unityDir = Directory(join(
      appHomeDir.androidDir.path,
      'unityLibrary',
    ));
    final localBundleDir = Directory(join(
      unityDir.path,
      'src',
      'main',
      'assets',
      'LocalBundles',
    ));
    if (localBundleDir.existsSync()) {
      /// cp -rf "$local_bundle_path" "$android_dir/app/src/main/assets"
      await ProcessRunner().runProcess(
        [
          'cp',
          '-rf',
          localBundleDir.path,
          "${appHomeDir.androidDir.path}/app/src/main/assets"
        ],
        workingDirectory: appHomeDir.androidDir,
        printOutput: true,
      );
    }

    /// rm -rf "$local_bundle_path"
    await ProcessRunner().runProcess(
      ['rm', '-rf', localBundleDir.path],
      workingDirectory: appHomeDir.androidDir,
      printOutput: true,
    );

    /// ./gradlew unityLibrary:bundleReleaseAar
    await ProcessRunner().runProcess(
      ['./gradlew', 'unityLibrary:bundleReleaseAar'],
      workingDirectory: appHomeDir.androidDir,
      printOutput: true,
    );
  }
}
