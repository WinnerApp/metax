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

    await _applyHvigorNodeOptions(appHomeDir.flutterDir);

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

    // Newer Flutter OHOS SDKs emit HARs to build/ohos/har/{debug|release}.
    // Older SDKs used .ohos/har — keep that as a fallback.
    final candidates = [
      Directory(join(
        appHomeDir.flutterDir.path,
        'build',
        'ohos',
        'har',
        configuration,
      )),
      Directory(join(appHomeDir.flutterDir.path, '.ohos', 'har')),
    ];
    final sourceHarDir = candidates.firstWhere(
      (dir) => dir.existsSync(),
      orElse: () => candidates.first,
    );
    if (!sourceHarDir.existsSync()) {
      throw Exception(
        'Flutter HAR 产物目录不存在，已检查: '
        '${candidates.map((e) => e.path).join(', ')}',
      );
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

  /// hvigorw 不读取 NODE_OPTIONS，仅认 hvigor-config.json5 的
  /// nodeOptions.maxOldSpaceSize。此处将 local.properties 中
  /// hvigor.nodeOptions 携带的 max-old-space-size 注入到
  /// .ohos/hvigor/hvigor-config.json5，用于低内存打包机缓解 swap 风暴。
  /// 必须在 cp -rf buildConfigs/ohos -> .ohos 之后调用，否则会被覆盖。
  Future<void> _applyHvigorNodeOptions(Directory flutterDir) async {
    final propsFile = File(join(flutterDir.path, 'local.properties'));
    if (!propsFile.existsSync()) {
      loggerDebug('local.properties 不存在，跳过 hvigor nodeOptions 注入');
      return;
    }
    String? nodeOptions;
    for (final line in propsFile.readAsLinesSync()) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) {
        continue;
      }
      final eq = trimmed.indexOf('=');
      if (eq <= 0) {
        continue;
      }
      if (trimmed.substring(0, eq).trim() == 'hvigor.nodeOptions') {
        nodeOptions = trimmed.substring(eq + 1).trim();
      }
    }
    if (nodeOptions == null || nodeOptions.isEmpty) {
      loggerDebug('local.properties 未配置 hvigor.nodeOptions，跳过注入');
      return;
    }
    final match = RegExp(r'max-old-space-size=(\d+)').firstMatch(nodeOptions);
    if (match == null) {
      loggerWarning(
        'hvigor.nodeOptions 中未找到 max-old-space-size，跳过注入: $nodeOptions',
      );
      return;
    }
    final maxOldSpaceSize = int.parse(match.group(1)!);

    final configPath = join(
      flutterDir.path,
      '.ohos',
      'hvigor',
      'hvigor-config.json5',
    );
    final configFile = File(configPath);
    if (!configFile.existsSync()) {
      loggerWarning('hvigor-config.json5 不存在，跳过 nodeOptions 注入: $configPath');
      return;
    }
    final config = configFile.readAsStringSync();
    if (config.contains('nodeOptions')) {
      loggerDebug('hvigor-config.json5 已包含 nodeOptions，跳过注入: $configPath');
      return;
    }
    final lastBrace = config.lastIndexOf('}');
    if (lastBrace < 0) {
      loggerWarning('hvigor-config.json5 格式异常，跳过 nodeOptions 注入: $configPath');
      return;
    }
    final inject =
        '\n  "nodeOptions": {"maxOldSpaceSize": $maxOldSpaceSize},';
    configFile.writeAsStringSync(
      config.substring(0, lastBrace) + inject + config.substring(lastBrace),
    );
    loggerInfo(
      '已注入 hvigor nodeOptions.maxOldSpaceSize=$maxOldSpaceSize 到 $configPath',
    );
  }
}
