import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:darty_json_safe/darty_json_safe.dart';
import 'package:meta_tool/app_home_dir.dart';
import 'package:meta_tool/appwrite_environment.dart';
import 'package:meta_tool/appwrite_server.dart';
import 'package:meta_tool/argument_get.dart';
import 'package:meta_tool/cache/cache_model.dart';
import 'package:meta_tool/cache/metax_cache.dart';
import 'package:meta_tool/commands/unity_environment.dart';
import 'package:meta_tool/common.dart';
import 'package:meta_tool/define.dart';
import 'package:path/path.dart';

class InitCacheCommand extends Command {
  @override
  String get description => '初始化缓存';

  @override
  String get name => 'cache';

  InitCacheCommand() {
    argParser.addOption(
      'workspace',
      help: '工作空间路径',
      defaultsTo: Directory.current.path,
    );
    argParser.addOption(
      'branch',
      help: '分支',
    );
    argParser.addOption(
      'unityBranch',
      help: 'unity分支',
    );
    argParser.addOption(
      'configuration',
      help: '请输入配置',
      allowed: BuildConfiguration.values.map((e) => e.name).toList(),
    );
    argParser.addOption(
      'isStore',
      help: '是否属于市场资源',
      allowed: ['true', 'false'],
    );
  }

  @override
  FutureOr? run() async {
    final workspace = argResults?['workspace'];
    final appHomeDir = AppHomeDir(workspace: workspace);
    final appwriteEnvironment = AppwriteCacheEnvironment();
    final unityEnvironment = UnityEnvironment();

    final flutterBranchs =
        await getLatestBranchList(appHomeDir.flutterDir.path);
    final branch = ArgumentGet(argResults).getString(
      'branch',
      '请选择Flutter分支',
      allowed: flutterBranchs,
    );
    final flutterSwitchBranch = getBranchName(branch);
    await switchBranch(appHomeDir.flutterDir.path, flutterSwitchBranch);
    final unityWorkspace = join(
      unityEnvironment.unityWorkspace,
      unityEnvironment.iosUnityPath,
    );
    final unityBranchs = await getLatestBranchList(unityWorkspace);
    final unityBranch = ArgumentGet(argResults).getString(
      'unityBranch',
      '请选择Unity分支',
      allowed: unityBranchs,
    );
    final unitySwitchBranch = getBranchName(unityBranch);
    await switchBranch(unityWorkspace, unitySwitchBranch);
    final configuration = ArgumentGet(argResults).getString(
      'configuration',
      '请选择构建配置',
      allowed: BuildConfiguration.values.map((e) => e.name).toList(),
    );
    final isStore = Unwrap(ArgumentGet(argResults).getString(
      'isStore',
      '请选择是否属于市场资源',
      allowed: ['true', 'false'],
    )).map((e) => e == 'true').defaultValue(false);
  }

  /// 构建缓存
  Future<void> buildCache({
    required AppwriteCacheEnvironment appwriteEnvironment,
    required UnityEnvironment unityEnvironment,
    required BuildPlatform buildPlatform,
    required BuildConfiguration buildConfiguration,
    required bool isStore,
    required BuildLibrary buildLibrary,
    required BuildType buildType,
    required String branch,
    required String commitHash,
  }) async {
    final appwriteService = AppwriteServer(
      endpoint: appwriteEnvironment.endpoint,
      projectId: appwriteEnvironment.projectId,
      apiKey: appwriteEnvironment.apiKey,
    );

    final metaxCache = MetaxCache(
      buildPlatform: buildPlatform,
      isStore: isStore,
      buildConfiguration: buildConfiguration,
      buildLibrary: buildLibrary,
      buildType: buildType,
      branch: branch,
    );

    /// 查询本地的缓存是否存在
    final metaxCacheManager = metaxCache.cacheManager;
    final cacheDatas = await metaxCacheManager.read();

    final branchCaches = cacheDatas
        .where((element) => element.branch == branch)
        .where((element) => element.buildPlatform == buildPlatform.name)
        .where((element) => element.isStore == isStore)
        .where((element) => element.configuration == buildConfiguration.name)
        .where((element) => element.buildLibrary == buildLibrary.name)
        .where((element) => element.buildType == buildType.name)
        .toList();

    List<int> buildIds = branchCaches.map((e) => int.parse(e.buildId)).toList();
    if (buildIds.isNotEmpty) {
      if (await metaxCache.isCacheExists(commitHash)) {
        loggerSuccess('检测本地已经存在对应commitHash的缓存，直接使用本地缓存!');
        return;
      } else {
        loggerWarning('检测本地已经存在对应分支缓存，直接使用当前分支最新的缓存!');
        buildIds.sort((a, b) => b.compareTo(a));
        final latestBuildId = buildIds.last;
        // branchCaches = branchCaches
        //     .where((element) => element.buildId == latestBuildId.toString())
        //     .;
        return;
      }
    }

    final caches = await appwriteService.queryZipCacheList(
      databaseId: appwriteEnvironment.databaseId,
      collectionId: appwriteEnvironment.collectionId,
      platform: buildPlatform.name,
      isStore: isStore,
      buildConfiguration: buildConfiguration.name,
      buildLibrary: buildLibrary.name,
      buildType: buildType.name,
    );
  }

  /// 从一组缓存数据获取最新的资源缓存
  CacheModel getLatestCache(List<CacheModel> caches) {
    if (caches.isEmpty) {
      throw Exception('没有找到对应的缓存数据');
    }
    caches.sort((a, b) => b.buildId.compareTo(a.buildId));
    return caches.first;
  }
}
