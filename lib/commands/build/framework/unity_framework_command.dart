import 'dart:io';

import 'package:meta_tool/cache/cache_manager.dart';
import 'package:meta_tool/cache/framework_aar_cache.dart';
import 'package:meta_tool/commands/build/build_cache_command.dart';
import 'package:meta_tool/common.dart';
import 'package:meta_tool/define.dart';
import 'package:path/path.dart';
import 'package:process_runner/process_runner.dart';

class UnityFrameworkCommand extends BuildCacheCommand {
  @override
  String get description => '打包Unity Framework';

  @override
  String get name => 'unity';

  @override
  Future<void> run() async {
    await super.run();
    final unityLibraryDir = join(appHomeDir.iosDir.path, 'UnityLibrary');
    final xcodeProjectPath = join(unityLibraryDir, 'Unity-iPhone.xcodeproj');
    if (!Directory(xcodeProjectPath).existsSync()) {
      throw '$unityLibraryDir 不存在';
    }
    final cacheManager = BuildCacheManager(unityLibraryDir);
    final models = await cacheManager.read();
    if (models.isEmpty) {
      throw '$unityLibraryDir 目录下缓存信息不存在!请先运行[metax build unity_cache ios]';
    }
    final cache = models.first;
    final unityCache = FrameworkCache(
      isStore: true,
      branch: cache.branch,
      buildConfiguration: BuildConfiguration.release,
      buildLibrary: BuildLibrary.unity,
    );
    final buildCacheDir = join(
      appHomeDir.workspace,
      'build',
      'Release-iphoneos',
    );
    await updateCache(
      cache: unityCache,
      commitHash: cache.commitHash,
      buildCacheDir: buildCacheDir,
      commitTime: cache.commitTime,
      cacheId: cache.buildId.toString(),
    );
    loggerSuccess('导出Unity Framework完成!');
    if (isUpload) {
      loggerDebug('上传缓存...');
      await uploadCacheResource(
        buildPlatform: BuildPlatform.ios,
        buildLibrary: BuildLibrary.unity,
        buildConfiguration: BuildConfiguration.release,
        buildType: BuildType.framework,
        isStore: true,
        branch: cache.branch,
        commitHash: cache.commitHash,
        commitTime: cache.commitTime,
      );
    }
  }

  @override
  Future<void> buildCache() async {
    await ProcessRunner().runProcess(
      [
        'xcodebuild',
        '-project',
        'Unity-iPhone.xcodeproj',
        '-scheme',
        'UnityFramework',
        '-configuration',
        'Release',
        '-sdk',
        'iphoneos',
        'BUILD_DIR=./build',
        'BUILD_ROOT=./build',
        'DEBUG_INFORMATION_FORMAT=dwarf-with-dsym',
        'clean',
        'build'
      ],
      workingDirectory: Directory(join(appHomeDir.iosDir.path, 'UnityLibrary')),
      printOutput: true,
    );
  }
}
