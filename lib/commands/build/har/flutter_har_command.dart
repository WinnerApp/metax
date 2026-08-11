import 'dart:io';

import 'package:meta_tool/argument_get.dart';
import 'package:meta_tool/cache/framework_aar_cache.dart';
import 'package:meta_tool/commands/build/build_cache_command.dart';
import 'package:meta_tool/common.dart';
import 'package:meta_tool/define.dart';
import 'package:meta_tool/flutter_sdk.dart';
import 'package:path/path.dart';
import 'package:process_runner/process_runner.dart';

class FlutterHarCommand extends BuildCacheCommand {
  @override
  String get description => '打包 Flutter HAR 并可选上传 Appwrite 缓存';

  @override
  String get name => 'flutter';

  FlutterHarCommand() {
    argParser.addOption(
      'configuration',
      abbr: 'c',
      help: 'flutter 工程配置，debug/release',
      allowed: BuildConfiguration.values.map((e) => e.name).toList(),
    );
    argParser.addOption(
      'branch',
      help: '分支名称，指定分支则切换到对应分支',
    );
  }

  late String configuration;
  late FlutterSdkInfo flutterSdk;
  late List<String> flutterCommand;

  @override
  Future<void> run() async {
    await super.run();
    if (useMock) {
      await copyDirToDir(
        MockType.flutterHar.mockDir(appHomeDir),
        MockType.flutterHar.sourceCacheDir(appHomeDir),
      );
      loggerSuccess('打包 Flutter HAR 完成!');
      return;
    }
    configuration = ArgumentGet(argResults).getString(
      'configuration',
      '请选择 Flutter HAR 构建配置',
      allowed: BuildConfiguration.values.map((e) => e.name).toList(),
    );
    final workspaceDir = appHomeDir.flutterDir;
    final pubspecFile = File(join(workspaceDir.path, 'pubspec.yaml'));
    if (!pubspecFile.existsSync()) {
      throw Exception('${workspaceDir.path} 不是一个 Flutter 工程');
    }
    final argBranch = argResults?['branch'];
    if (argBranch != null) {
      if (skipGitPull) {
        loggerInfo('跳过 Git 操作模式，使用本地代码');
      } else {
        await switchBranch(workspaceDir.path, argBranch);
      }
    }

    final gate = await ensureFlutterSdkReady(workspaceDir);
    flutterSdk = gate.sdk;
    flutterCommand = flutterSdk.flutterCommand;

    final branch = await getCurrentBranch(workspaceDir.path);
    final commitHash = await getCurrentCommitHash(workspaceDir.path);
    final commitTime = await getCommitTime(workspaceDir.path, commitHash);
    final buildConfiguration = BuildConfiguration.values.firstWhere(
      (e) => e.name == configuration,
    );
    final flutterCache = HarCache(
      branch: branch,
      buildConfiguration: buildConfiguration,
      buildLibrary: BuildLibrary.flutter,
      buildId: 0,
    );
    final buildCacheDir = join(
      appHomeDir.ohosDir.path,
      'aar',
      'flutter',
      configuration,
    );
    await updateCache(
      cache: flutterCache,
      commitHash: commitHash,
      buildCacheDir: buildCacheDir,
      commitTime: commitTime,
      cacheId: commitHash,
      forceUpdate: forceUpdate || gate.didClean,
      flutterSdk: flutterSdk.fingerprint,
    );
    await saveFlutterSdkFingerprint(
      projectPath: workspaceDir.path,
      sdk: flutterSdk,
    );
    loggerSuccess('导出 Flutter HAR 完成!');
    if (isUpload) {
      loggerDebug('上传缓存...');
      await uploadCacheResource(
        buildPlatform: BuildPlatform.ohos,
        buildLibrary: BuildLibrary.flutter,
        buildConfiguration: buildConfiguration,
        buildType: BuildType.har,
        branch: branch,
        commitHash: commitHash,
        commitTime: commitTime,
        buildId: 0,
      );
    }
  }

  @override
  Future<void> buildCache() async {
    await ProcessRunner().runProcess(
      [...flutterCommand, 'pub', 'get'],
      workingDirectory: appHomeDir.flutterDir,
      printOutput: true,
    );

    final ohosConfigDir =
        Directory(join(appHomeDir.flutterDir.path, 'buildConfigs', 'ohos'));
    if (ohosConfigDir.existsSync()) {
      final toConfigDir = Directory(join(appHomeDir.flutterDir.path, '.ohos'));
      if (!toConfigDir.existsSync()) {
        throw Exception('.ohos 目录不存在: ${toConfigDir.path}');
      }
      await ProcessRunner().runProcess(
        ['cp', '-rf', '${ohosConfigDir.path}/.', toConfigDir.path],
        workingDirectory: appHomeDir.flutterDir,
        printOutput: true,
      );
    }

    final modeFlag =
        configuration == BuildConfiguration.debug.name ? '--debug' : '--release';
    await ProcessRunner().runProcess(
      [
        ...flutterCommand,
        'build',
        'har',
        modeFlag,
        '--target-platform=ohos-arm64',
      ],
      workingDirectory: appHomeDir.flutterDir,
      printOutput: true,
    );

    final sourceHarDir =
        Directory(join(appHomeDir.flutterDir.path, '.ohos', 'har'));
    if (!sourceHarDir.existsSync()) {
      throw Exception('Flutter HAR 产物目录不存在: ${sourceHarDir.path}');
    }
    final stableDir = Directory(join(
      appHomeDir.ohosDir.path,
      'aar',
      'flutter',
      configuration,
    ));
    if (stableDir.existsSync()) {
      await stableDir.delete(recursive: true);
    }
    await copyDirToDir(sourceHarDir, stableDir);
    loggerDebug('已收集 Flutter HAR 到 ${stableDir.path}');
  }
}
