import 'dart:io';

import 'package:darty_json_safe/darty_json_safe.dart';
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
    argParser.addOption('workspace', abbr: 's', help: 'unity工程目录，默认使用当前目录');
  }

  late String workspace;

  @override
  Future<void> run() async {
    workspace = argResults?['workspace'] ?? Directory.current.path;
    final workspaceDir = Directory(workspace);
    final xcodeProjectPath = join(workspaceDir.path, 'Unity-iPhone.xcodeproj');
    if (!Directory(xcodeProjectPath).existsSync()) {
      throw '当前目录不是iOS Unity工程目录';
    }
    final buildIdFile = File(join(workspaceDir.path, '.build_id'));
    if (!buildIdFile.existsSync()) {
      throw '$buildIdFile 不存在，请先运行 metax build unity';
    }
    final jsonText = await buildIdFile.readAsString().catchError((e) => '{}');
    final json = JSON(jsonText);
    final branch = json['branch'].string;
    final commitHash = json['commitHash'].string;
    if (branch == null || commitHash == null) {
      throw 'buildIdFile 格式错误，请先运行 metax build unity';
    }
    final unityCache = FrameworkAarCache(
      platform: BuildPlatform.ios,
      configuration: BuildConfiguration.release,
      type: BuildType.framework,
      library: BuildLibrary.unity,
    );
    final buildCacheDir = join(
      workspace,
      'build',
      'Release-iphoneos',
    );
    await updateCache(
      cache: unityCache,
      branch: branch,
      commitHash: commitHash,
      buildCacheDir: buildCacheDir,
    );
    loggerSuccess('导出Unity Framework完成!');
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
