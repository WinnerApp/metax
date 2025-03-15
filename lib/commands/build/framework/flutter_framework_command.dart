import 'dart:io';

import 'package:darty_json_safe/darty_json_safe.dart';
import 'package:meta_tool/argument_get.dart';
import 'package:meta_tool/cache/framework_aar_cache.dart';
import 'package:meta_tool/commands/build/build_cache_command.dart';
import 'package:meta_tool/common.dart';
import 'package:meta_tool/define.dart';
import 'package:path/path.dart';
import 'package:process_runner/process_runner.dart';

class FlutterFrameworkCommand extends BuildCacheCommand {
  @override
  String get description => '编译Flutter Framework';

  @override
  String get name => 'flutter';

  FlutterFrameworkCommand() {
    argParser.addOption(
      'workspace',
      abbr: 's',
      help: 'flutter工程目录，默认使用当前目录',
      defaultsTo: Directory.current.path,
    );
    argParser.addOption(
      'configuration',
      abbr: 'c',
      help: 'flutter工程配置，debug/release',
      allowed: ['debug', 'release'],
    );
    argParser.addOption(
      'isStore',
      help: '是否发布包',
      allowed: ['true', 'false'],
    );
    argParser.addFlag(
      'isUpload',
      defaultsTo: true,
      help: '是否上传缓存,默认上传',
    );
  }

  late String workspace;
  late String configuration;
  late bool isStore;
  @override
  Future<void> run() async {
    workspace = argResults?['workspace'];
    configuration = ArgumentGet(argResults).getString(
      'configuration',
      '请选择Flutter Framework构建配置',
      allowed: BuildConfiguration.values.map((e) => e.name).toList(),
    );
    if (configuration == 'debug') {
      isStore = false;
    } else {
      isStore = Unwrap(ArgumentGet(argResults).getString(
        'isStore',
        '是否应用市场的Flutter Framework',
        allowed: ['true', 'false'],
      )).map((e) => e == 'true').defaultValue(false);
    }
    final isUpload = argResults?['isUpload'];
    final pubspecFile = File(join(workspace, 'pubspec.yaml'));
    if (!pubspecFile.existsSync()) {
      throw Exception('pubspec.yaml文件不存在: ${pubspecFile.path}');
    }
    if (!await isGitRepository(workspace)) {
      throw Exception('当前目录不是git仓库: $workspace');
    }

    final branch = await getCurrentBranch(workspace);
    final commitHash = await getCurrentCommitHash(workspace);
    final commitTime = await getCommitTime(workspace, commitHash);
    BuildConfiguration buildConfiguration;
    if (isStore) {
      buildConfiguration = BuildConfiguration.release;
    } else {
      buildConfiguration = configuration == 'debug'
          ? BuildConfiguration.debug
          : BuildConfiguration.release;
    }
    final flutterCache = FrameworkCache(
      buildConfiguration: buildConfiguration,
      buildLibrary: BuildLibrary.flutter,
      isStore: isStore,
      branch: branch,
    );
    late String buildCacheDir;
    if (configuration == 'debug') {
      buildCacheDir = join(workspace, 'build', 'ios', 'framework', 'Debug');
    } else {
      buildCacheDir = join(workspace, 'build', 'ios', 'framework', 'Release');
    }
    await updateCache(
      cache: flutterCache,
      commitHash: commitHash,
      buildCacheDir: buildCacheDir,
      commitTime: commitTime,
      cacheId: commitHash,
    );
    loggerSuccess('导出Flutter Framework完成!');
    if (isUpload) {
      loggerDebug('上传缓存...');
      await uploadCacheResource(
        buildPlatform: BuildPlatform.ios,
        buildLibrary: BuildLibrary.flutter,
        buildConfiguration: buildConfiguration,
        buildType: BuildType.framework,
        isStore: isStore,
        branch: branch,
        commitHash: commitHash,
        commitTime: commitTime,
      );
    }
  }

  @override
  Future<void> buildCache() async {
    /// flutter pub get
    await ProcessRunner().runProcess(
      ['flutter', 'pub', 'get'],
      workingDirectory: Directory(workspace),
      printOutput: true,
    );
    if (configuration == 'debug') {
      /// flutter build ios-framework --no-profile --no-release --xcframework --cocoapods --verbose
      await ProcessRunner().runProcess(
        [
          'flutter',
          'build',
          'ios-framework',
          '--no-profile',
          '--no-release',
          '--xcframework',
          '--cocoapods',
          '--verbose'
        ],
        workingDirectory: Directory(workspace),
        printOutput: true,
      );
    } else {
      /// flutter build ios-framework --no-debug --no-profile --xcframework --cocoapods --verbose
      await ProcessRunner().runProcess(
        [
          'flutter',
          'build',
          'ios-framework',
          '--no-debug',
          '--no-profile',
          '--xcframework',
          '--cocoapods',
          '--verbose'
        ],
        workingDirectory: Directory(workspace),
        printOutput: true,
      );
    }
  }
}
