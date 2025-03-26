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
  }

  late String configuration;
  late bool isStore;
  @override
  Future<void> run() async {
    await super.run();
    isStore = Unwrap(ArgumentGet(argResults).getString(
      'isStore',
      '是否应用市场的Flutter Framework',
      allowed: ['true', 'false'],
    )).map((e) => e == 'true').defaultValue(false);
    if (isStore) {
      configuration = 'release';
    } else {
      configuration = ArgumentGet(argResults).getString(
        'configuration',
        '请选择Flutter Framework构建配置',
        allowed: BuildConfiguration.values.map((e) => e.name).toList(),
      );
    }
    final flutterDir = appHomeDir.flutterDir;
    final pubspecFile = File(join(flutterDir.path, 'pubspec.yaml'));
    if (!pubspecFile.existsSync()) {
      throw Exception('${flutterDir.path} 不是一个Flutter工程');
    }
    if (!await isGitRepository(flutterDir.path)) {
      throw Exception('${flutterDir.path} 不是一个git仓库');
    }

    final branch = await getCurrentBranch(flutterDir.path);
    final commitHash = await getCurrentCommitHash(flutterDir.path);
    final commitTime = await getCommitTime(flutterDir.path, commitHash);
    BuildConfiguration buildConfiguration;
    if (isStore) {
      buildConfiguration = BuildConfiguration.release;
    } else {
      buildConfiguration = BuildConfiguration.values.firstWhere(
        (e) => e.name == configuration,
      );
    }
    final flutterCache = FrameworkCache(
      buildConfiguration: buildConfiguration,
      buildLibrary: BuildLibrary.flutter,
      isStore: isStore,
      branch: branch,
    );
    late String buildCacheDir;
    if (configuration == 'debug') {
      buildCacheDir =
          join(flutterDir.path, 'build', 'ios', 'framework', 'Debug');
    } else {
      buildCacheDir =
          join(flutterDir.path, 'build', 'ios', 'framework', 'Release');
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
      workingDirectory: appHomeDir.flutterDir,
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
        workingDirectory: appHomeDir.flutterDir,
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
        workingDirectory: appHomeDir.flutterDir,
        printOutput: true,
      );
    }
  }
}
