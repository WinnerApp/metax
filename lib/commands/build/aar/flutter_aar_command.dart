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

  late String configuration;
  late bool isStore;
  @override
  Future<void> run() async {
    await super.run();
    if (useMock) {
      await copyDirToDir(
        MockType.flutterAar.mockDir(appHomeDir),
        MockType.flutterAar.sourceCacheDir(appHomeDir),
      );
      loggerSuccess('打包Flutter AAR完成!');
      return;
    }
    isStore = Unwrap(ArgumentGet(argResults).getString(
      'isStore',
      '是否应用市场的Flutter AAR',
      allowed: ['true', 'false'],
    )).map((e) => e == 'true').defaultValue(false);
    if (isStore) {
      configuration = 'release';
    } else {
      configuration = ArgumentGet(argResults).getString(
        'configuration',
        '请选择Flutter AAR构建配置',
        allowed: BuildConfiguration.values.map((e) => e.name).toList(),
      );
    }
    final workspaceDir = appHomeDir.flutterDir;
    final pubspecFile = File(join(workspaceDir.path, 'pubspec.yaml'));
    if (!pubspecFile.existsSync()) {
      throw Exception('${workspaceDir.path} 不是一个Flutter工程');
    }
    final branch = await getCurrentBranch(workspaceDir.path);
    final commitHash = await getCurrentCommitHash(workspaceDir.path);
    final commitTime = await getCommitTime(workspaceDir.path, commitHash);
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
    final buildCacheDir = join(workspaceDir.path, 'build', 'host');
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
      workingDirectory: appHomeDir.flutterDir,
      printOutput: true,
    );
    // metaapp_flutter/buildConfigs/android
    final androidConfigDir =
        Directory(join(appHomeDir.flutterDir.path, 'buildConfigs', 'android'));
    if (!androidConfigDir.existsSync()) {
      throw Exception('buildConfigs/android目录不存在: ${androidConfigDir.path}');
    }

    final toConfigDir = Directory(join(appHomeDir.flutterDir.path, '.android'));
    if (!toConfigDir.existsSync()) {
      throw Exception('.android目录不存在: ${toConfigDir.path}');
    }

    if (await androidConfigDir.exists()) {
      /// cp -r -f "$android_config_dir"/* "$generate_android_dir"
      await ProcessRunner().runProcess(
        ['cp', '-rf', "${androidConfigDir.path}/.", toConfigDir.path],
        workingDirectory: appHomeDir.flutterDir,
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
          '--target-platform=android-arm64',
          '--verbose',
        ],
        workingDirectory: appHomeDir.flutterDir,
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
          '--target-platform=android-arm64',
          '--verbose',
        ],
        workingDirectory: appHomeDir.flutterDir,
        printOutput: true,
      );
    }
  }
}
