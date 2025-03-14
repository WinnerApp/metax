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

  UnityFrameworkCommand() {
    argParser.addOption(
      'workspace',
      abbr: 's',
      help: 'unity工程目录，默认使用当前目录',
    );
    argParser.addFlag(
      'isUpload',
      defaultsTo: true,
      help: '是否上传缓存,默认上传',
    );
  }

  late String workspace;

  @override
  Future<void> run() async {
    workspace = argResults?['workspace'] ?? Directory.current.path;
    final isUpload = argResults?['isUpload'];
    final workspaceDir = Directory(workspace);
    final xcodeProjectPath = join(workspaceDir.path, 'Unity-iPhone.xcodeproj');
    if (!Directory(xcodeProjectPath).existsSync()) {
      throw '当前目录不是iOS Unity工程目录';
    }
    final buildId = await getUnityBuildVersion(workspace);
    final cacheManager = BuildCacheManager(workspace);
    final models = await cacheManager.read();
    final model = models.where((e) => e.buildId == buildId.toString()).toList();
    if (model.isEmpty) {
      throw '$workspace 目录下缓存信息不存在!请先运行[metax build unity_cache ios]';
    }
    final cache = model.first;
    final unityCache = FrameworkCache(
      isStore: true,
      branch: cache.branch,
      buildConfiguration: BuildConfiguration.release,
      buildLibrary: BuildLibrary.unity,
    );
    final buildCacheDir = join(
      workspace,
      'build',
      'Release-iphoneos',
    );
    await updateCache(
      cache: unityCache,
      commitHash: cache.commitHash,
      buildCacheDir: buildCacheDir,
      commitTime: cache.commitTime,
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
      workingDirectory: Directory(workspace),
      printOutput: true,
    );
  }
}
