import 'dart:io';

import 'package:darty_json_safe/darty_json_safe.dart';
import 'package:meta_tool/argument_get.dart';
import 'package:meta_tool/cache/framework_aar_cache.dart';
import 'package:meta_tool/commands/build/build_cache_command.dart';
import 'package:meta_tool/common.dart';
import 'package:meta_tool/define.dart';
import 'package:path/path.dart';
import 'package:process_runner/process_runner.dart';

class FlutterAarCommand extends BuildCacheCommand {
  @override
  String get description => '打包flutter aar';

  @override
  String get name => 'flutter';

  FlutterAarCommand() {
    argParser.addOption(
      'configuration',
      abbr: 'c',
      help: 'flutter工程配置，debug/release',
      allowed: BuildConfiguration.values.map((e) => e.name).toList(),
    );
    argParser.addOption(
      'isStore',
      help: '是否发布包',
      allowed: ['true', 'false'],
    );
  }

  late String workspace;
  late String configuration;
  late bool isStore;
  @override
  Future<void> run() async {
    await super.run();
    configuration = ArgumentGet(argResults).getString(
      'configuration',
      '请选择Flutter AAR构建配置',
      allowed: BuildConfiguration.values.map((e) => e.name).toList(),
    );
    if (configuration == 'debug') {
      isStore = false;
    } else {
      isStore = Unwrap(ArgumentGet(argResults).getString(
        'isStore',
        '是否应用市场的Flutter AAR',
        allowed: ['true', 'false'],
      )).map((e) => e == 'true').defaultValue(false);
    }
    final workspaceDir = appHomeDir.flutterDir;
    final pubspecFile = File(join(workspaceDir.path, 'pubspec.yaml'));
    if (!pubspecFile.existsSync()) {
      throw Exception('${workspaceDir.path} 不是一个Flutter工程');
    }
    final branch = await getCurrentBranch(workspace);
    final commitHash = await getCurrentCommitHash(workspace);
    final commitTime = await getCommitTime(workspace, commitHash);
    BuildConfiguration buildConfiguration;
    if (isStore) {
      buildConfiguration = BuildConfiguration.release;
    } else {
      buildConfiguration = BuildConfiguration.values.firstWhere(
        (e) => e.name == configuration,
      );
    }
    final flutterCache = AarCache(
      isStore: isStore,
      branch: branch,
      buildConfiguration: buildConfiguration,
      buildLibrary: BuildLibrary.flutter,
    );
    final buildCacheDir = join(workspace, 'build', 'host');
    await updateCache(
      cache: flutterCache,
      commitHash: commitHash,
      buildCacheDir: buildCacheDir,
      commitTime: commitTime,
      cacheId: commitHash,
    );
    loggerSuccess('导出Flutter AAR完成!');
    if (isUpload) {
      loggerDebug('上传缓存...');
      await uploadCacheResource(
        buildPlatform: BuildPlatform.android,
        buildLibrary: BuildLibrary.flutter,
        buildConfiguration: buildConfiguration,
        buildType: BuildType.aar,
        isStore: isStore,
        branch: branch,
        commitHash: commitHash,
        commitTime: commitTime,
      );
    }
  }

  @override
  Future<void> buildCache() async {
    // flutter pub get
    await ProcessRunner().runProcess(
      ['flutter', 'pub', 'get'],
      workingDirectory: Directory(workspace),
      printOutput: true,
    );
    // metaapp_flutter/buildConfigs/android
    final androidConfigDir =
        Directory(join(workspace, 'buildConfigs', 'android'));
    if (!androidConfigDir.existsSync()) {
      throw Exception('buildConfigs/android目录不存在: ${androidConfigDir.path}');
    }

    final toConfigDir = Directory(join(workspace, '.android'));
    if (!toConfigDir.existsSync()) {
      throw Exception('.android目录不存在: ${toConfigDir.path}');
    }

    if (await androidConfigDir.exists()) {
      /// cp -r -f "$android_config_dir"/* "$generate_android_dir"
      await ProcessRunner().runProcess(
        ['cp', '-rf', "${androidConfigDir.path}/.", toConfigDir.path],
        workingDirectory: Directory(workspace),
        printOutput: true,
      );
    }

    if (configuration == 'debug') {
      /// flutter build aar --no-profile --no-release --verbose
      await ProcessRunner().runProcess(
        [
          'flutter',
          'build',
          'aar',
          '--no-profile',
          '--no-release',
          '--verbose'
        ],
        workingDirectory: Directory(workspace),
        printOutput: true,
      );
    } else {
      /// flutter build aar --no-debug --no-profile --verbose
      await ProcessRunner().runProcess(
        [
          'flutter',
          'build',
          'aar',
          '--no-debug',
          '--no-profile',
          '--verbose',
        ],
        workingDirectory: Directory(workspace),
        printOutput: true,
      );
    }
  }
}
