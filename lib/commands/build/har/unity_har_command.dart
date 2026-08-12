import 'dart:io';

import 'package:meta_tool/cache/cache_manager.dart';
import 'package:meta_tool/cache/framework_aar_cache.dart';
import 'package:meta_tool/commands/build/build_cache_command.dart';
import 'package:meta_tool/common.dart';
import 'package:meta_tool/define.dart';
import 'package:path/path.dart';
import 'package:process_runner/process_runner.dart';

class UnityHarCommand extends BuildCacheCommand {
  @override
  String get description => '打包 Unity/团结 HAR（鸿蒙）并可选上传 Appwrite 缓存';

  @override
  String get name => 'unity';

  UnityHarCommand() {
    argParser.addOption(
      'module',
      help: 'hvigor 模块名',
      defaultsTo: 'tuanjieLib',
    );
    argParser.addOption(
      'product',
      help: 'hvigor product',
      defaultsTo: 'default',
    );
    argParser.addOption(
      'configuration',
      abbr: 'c',
      help: '构建配置 debug/release（对应 buildMode）',
      allowed: BuildConfiguration.values.map((e) => e.name).toList(),
      defaultsTo: BuildConfiguration.release.name,
    );
  }

  late String module;
  late String product;
  late String configuration;
  late String hvigorw;

  /// 稳定产物目录：ohos/aar/unity/tuanjieLib.har
  String get _stableHarDir => join(appHomeDir.ohosDir.path, 'aar', 'unity');

  String get _stableHarFileName => '$module.har';

  @override
  Future<void> run() async {
    await super.run();

    module = argResults?['module'] as String? ?? 'tuanjieLib';
    product = argResults?['product'] as String? ?? 'default';
    configuration = argResults?['configuration'] as String? ??
        BuildConfiguration.release.name;

    final ohosDir = appHomeDir.ohosDir;
    if (!ohosDir.existsSync()) {
      throw Exception('ohos 目录不存在: ${ohosDir.path}');
    }

    final unityDir = _resolveUnityLibraryDir();
    if (!unityDir.existsSync()) {
      throw Exception(
        'Unity Library 目录不存在: ${unityDir.path}，请先运行: metax build unity_cache ohos',
      );
    }

    if (useMock) {
      await copyDirToDir(
        MockType.unityHar.mockDir(appHomeDir),
        MockType.unityHar.sourceCacheDir(appHomeDir),
      );
      loggerSuccess('打包 Unity HAR 完成!');
      return;
    }

    hvigorw = await _resolveHvigorw(ohosDir);

    final cacheManager = BuildCacheManager(unityDir.path);
    final models = await cacheManager.read();
    if (models.isEmpty) {
      throw Exception('未找到 Unity 缓存数据，请先运行: metax build unity_cache ohos');
    }
    final cache = models.first;
    final branch = cache.branch;
    final commitHash = cache.commitHash;
    final commitTime = cache.commitTime;
    final buildId = cache.buildId;
    final buildConfiguration = BuildConfiguration.values.firstWhere(
      (e) => e.name == configuration,
    );
    final unityCache = HarCache(
      branch: branch,
      buildConfiguration: buildConfiguration,
      buildLibrary: BuildLibrary.unity,
      buildId: int.parse(buildId),
    );
    await updateCache(
      cache: unityCache,
      commitHash: commitHash,
      buildCacheDir: _stableHarDir,
      commitTime: commitTime,
      cacheId: cache.buildId.toString(),
      forceUpdate: forceUpdate,
    );

    loggerSuccess('打包 Unity HAR 完成!');
    if (isUpload) {
      loggerDebug('上传缓存...');
      await uploadCacheResource(
        buildPlatform: BuildPlatform.ohos,
        buildLibrary: BuildLibrary.unity,
        buildConfiguration: buildConfiguration,
        buildType: BuildType.har,
        branch: branch,
        commitHash: commitHash,
        commitTime: commitTime,
        buildId: int.parse(buildId),
      );
    }
  }

  @override
  Future<void> buildCache() async {
    final ohosDir = appHomeDir.ohosDir;
    await ProcessRunner().runProcess(
      [
        hvigorw,
        'assembleHar',
        '-p',
        'module=$module',
        '-p',
        'product=$product',
        '-p',
        'buildMode=$configuration',
        '--no-daemon',
      ],
      workingDirectory: ohosDir,
      printOutput: true,
    );

    final harFiles = _findHarOutputs(ohosDir);
    if (harFiles.isEmpty) {
      throw Exception(
        '未找到 $module 的 .har 产物，已检查: ${_harOutputCandidates(ohosDir).join(', ')}',
      );
    }

    final stableDir = Directory(_stableHarDir);
    if (stableDir.existsSync()) {
      await stableDir.delete(recursive: true);
    }
    await stableDir.create(recursive: true);
    final preferred = harFiles.where(
      (e) => basename(e.path) == _stableHarFileName,
    );
    final sourceHar = preferred.isNotEmpty ? preferred.first : harFiles.first;
    final targetHar = File(join(stableDir.path, _stableHarFileName));
    await copyFile(sourceHar, targetHar);
    loggerDebug('已收集 HAR 到 ${targetHar.path}');
  }

  /// 优先使用项目内 ohos/hvigorw，其次 PATH 中的全局 hvigorw。
  Future<String> _resolveHvigorw(Directory ohosDir) async {
    final local = File(join(ohosDir.path, 'hvigorw'));
    if (local.existsSync()) {
      return './hvigorw';
    }

    try {
      final result = await ProcessRunner().runProcess(
        ['which', 'hvigorw'],
        printOutput: false,
      );
      final path = result.output.trim();
      if (path.isNotEmpty && File(path).existsSync()) {
        loggerDebug('使用全局 hvigorw: $path');
        return path;
      }
    } catch (_) {
      // which 失败时统一抛下方错误
    }

    throw Exception(
      '找不到 hvigorw：项目 ohos 目录无本地脚本，且 PATH 中也没有全局命令',
    );
  }

  /// 优先使用 ohos/unityLibrary（unity_cache 导出目录），其次模块同名目录
  Directory _resolveUnityLibraryDir() {
    final unityLibrary =
        Directory(join(appHomeDir.ohosDir.path, 'unityLibrary'));
    if (unityLibrary.existsSync()) {
      return unityLibrary;
    }
    return Directory(join(appHomeDir.ohosDir.path, module));
  }

  List<String> _harOutputCandidates(Directory ohosDir) {
    return [
      // 团结导出：ohos/unityLibrary/tuanjieLib/build/default/outputs/default/
      join(
        ohosDir.path,
        'unityLibrary',
        module,
        'build',
        product,
        'outputs',
        product,
      ),
      join(ohosDir.path, module, 'build', product, 'outputs', product),
      join(ohosDir.path, 'unityLibrary', 'build', product, 'outputs', product),
    ];
  }

  List<File> _findHarOutputs(Directory ohosDir) {
    final files = <File>[];
    for (final path in _harOutputCandidates(ohosDir)) {
      final dir = Directory(path);
      if (!dir.existsSync()) {
        continue;
      }
      files.addAll(
        dir
            .listSync()
            .whereType<File>()
            .where((e) => e.path.endsWith('.har')),
      );
    }
    return files;
  }
}
