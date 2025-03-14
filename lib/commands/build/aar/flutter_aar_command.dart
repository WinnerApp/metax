import 'dart:io';

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
    argParser.addOption('workspace', abbr: 's', help: 'flutter工程目录，默认使用当前目录');
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
    argParser.addFlag(
      'isUpload',
      help: '是否上传缓存,默认上传',
      defaultsTo: true,
    );
  }

  late String workspace;
  late String configuration;
  late bool isStore;
  @override
  Future<void> run() async {
    workspace = argResults?['workspace'] ?? Directory.current.path;
    configuration = ArgumentGet(argResults).getString(
      'configuration',
      allowed: BuildConfiguration.values.map((e) => e.name).toList(),
    );
    if (configuration == 'debug') {
      isStore = false;
    } else {
      isStore = ArgumentGet(argResults).getString(
            'isStore',
            allowed: ['true', 'false'],
          ) ==
          'true';
    }
    final isUpload = argResults?['isUpload'];
    final workspaceDir = Directory(workspace);
    final pubspecFile = File(join(workspaceDir.path, 'pubspec.yaml'));
    if (!pubspecFile.existsSync()) {
      throw Exception('pubspec.yaml文件不存在: ${pubspecFile.path}');
    }
    final branch = await getCurrentBranch(workspace);
    final commitHash = await getCurrentCommitHash(workspace);
    BuildConfiguration buildConfiguration;
    if (isStore) {
      buildConfiguration = BuildConfiguration.release;
    } else {
      buildConfiguration = configuration == 'debug'
          ? BuildConfiguration.debug
          : BuildConfiguration.release;
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
