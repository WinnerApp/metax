import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:darty_json_safe/darty_json_safe.dart';
import 'package:meta_tool/app_home_dir.dart';
import 'package:meta_tool/argument_get.dart';
import 'package:meta_tool/cache/cache_manager.dart';
import 'package:meta_tool/cache/cache_model.dart';
import 'package:meta_tool/cache/metax_cache.dart';
import 'package:meta_tool/common.dart';
import 'package:meta_tool/define.dart';
import 'package:path/path.dart';
import 'package:prompts/prompts.dart' as prompts;

class UseCacheCommand extends Command {
  @override
  String get description => '使用缓存';

  @override
  String get name => 'use';

  UseCacheCommand() {
    argParser.addOption(
      'workspace',
      help: 'App工作区,默认为当前目录',
      defaultsTo: Directory.current.path,
    );
    argParser.addOption(
      'buildPlatform',
      help: '构建平台',
      allowed: BuildPlatform.values.map((e) => e.name),
    );
    argParser.addOption(
      'buildConfiguration',
      help: '构建配置',
      allowed: BuildConfiguration.values.map((e) => e.name),
    );

    argParser.addOption(
      'buildLibrary',
      help: '构建库',
      allowed: BuildLibrary.values.map((e) => e.name),
    );
    argParser.addOption(
      'buildType',
      help: '构建类型',
      allowed: BuildType.values.map((e) => e.name),
    );
    argParser.addOption(
      'branch',
      help: '分支',
      defaultsTo: 'master',
    );
    argParser.addFlag(
      'isStore',
      help: '是否发布包缓存',
      defaultsTo: false,
    );
    argParser.addOption(
      'commitHash',
      help: 'Git Hash',
    );
    argParser.addOption(
      'buildId',
      help: '构建ID',
    );
  }

  late String buildPlatform;
  late String buildLibrary;
  late String buildConfiguration;
  late String buildType;
  late bool isStore;

  @override
  Future<void> run() async {
    final workspace = argResults?['workspace'];
    final appHomeDir = AppHomeDir(workspace: workspace);
    final metaxCacheManager = MetaxCacheManager();
    final cacheModels = await metaxCacheManager.read();
    buildPlatform = ArgumentGet(argResults).getString(
      'buildPlatform',
      '请选择构建平台',
      allowed: BuildPlatform.values.map((e) => e.name).toList(),
    );
    buildLibrary = ArgumentGet(argResults).getString(
      'buildLibrary',
      '请选择构建库',
      allowed: BuildLibrary.values.map((e) => e.name).toList(),
    );
    if (buildLibrary == BuildLibrary.flutter.name) {
      buildConfiguration = ArgumentGet(argResults).getString(
        'buildConfiguration',
        '请选择构建配置',
        allowed: BuildConfiguration.values.map((e) => e.name).toList(),
      );
    } else {
      buildConfiguration = 'release';
    }

    buildType = ArgumentGet(argResults).getString(
      'buildType',
      '请选择构建类型',
      allowed: BuildType.values.map((e) => e.name).toList(),
    );

    if (buildConfiguration == BuildConfiguration.debug.name) {
      isStore = false;
    } else if (buildType == BuildType.library.name) {
      isStore = true;
    } else {
      isStore = Unwrap(prompts.choose(
        '是否使用发布包缓存',
        ['true', 'false'],
      )).map((e) => e == 'true').defaultValue(false);
    }

    List<CacheModel> filterCacheModels = cacheModels
        .where((e) =>
            e.buildPlatform == buildPlatform &&
            e.buildLibrary == buildLibrary &&
            e.configuration == buildConfiguration &&
            e.buildType == buildType &&
            e.isStore == isStore)
        .toList();

    final branchs = filterCacheModels.map((e) => e.branch).toList();
    if (filterCacheModels.isEmpty) {
      throw Exception('没有找到分支缓存');
    }

    final chooseBranch = ArgumentGet(argResults).getString(
      'branch',
      '请选择分支',
      allowed: branchs,
    );

    filterCacheModels =
        filterCacheModels.where((e) => e.branch == chooseBranch).toList();

    final buildIds = filterCacheModels.map((e) => e.buildId).toList();
    String chooseBuildId = ArgumentGet(argResults).getString(
      'buildId',
      '请选择构建ID',
      allowed: buildIds,
    );

    filterCacheModels =
        filterCacheModels.where((e) => e.buildId == chooseBuildId).toList();

    final commitHashs = filterCacheModels.map((e) => e.commitHash).toList();
    String chooseCommitHash = ArgumentGet(argResults).getString(
      'commitHash',
      '请选择上传Hash',
      allowed: commitHashs,
    );

    final cacheModel =
        filterCacheModels.firstWhere((e) => e.commitHash == chooseCommitHash);

    final metaxCache = MetaxCache(
      buildPlatform: BuildPlatform.values.firstWhere(
        (e) => e.name == buildPlatform,
      ),
      buildLibrary: BuildLibrary.values.firstWhere(
        (e) => e.name == buildLibrary,
      ),
      buildConfiguration: BuildConfiguration.values.firstWhere(
        (e) => e.name == buildConfiguration,
      ),
      buildType: BuildType.values.firstWhere(
        (e) => e.name == buildType,
      ),
      branch: chooseBranch,
      isStore: isStore,
      buildId: int.parse(chooseBuildId),
    );

    late String copyCacheToDir;
    if (buildPlatform == BuildPlatform.ios.name) {
      if (buildType == BuildType.library.name) {
        copyCacheToDir = join(
          appHomeDir.iosDir.path,
          'UnityLibrary',
        );
      } else {
        if (buildConfiguration == BuildConfiguration.debug.name) {
          copyCacheToDir = join(
            appHomeDir.iosDir.path,
            'framework',
            'flutter',
            'Debug',
          );
        } else {
          if (buildLibrary == BuildLibrary.flutter.name) {
            copyCacheToDir = join(
              appHomeDir.iosDir.path,
              'framework',
              'flutter',
              'Release',
            );
          } else {
            copyCacheToDir = join(
              appHomeDir.iosDir.path,
              'framework',
              'unity',
            );
          }
        }
      }
    } else {
      if (buildType == BuildType.library.name) {
        copyCacheToDir = join(appHomeDir.androidDir.path, 'unityLibrary');
      } else {
        if (buildLibrary == BuildLibrary.flutter.name) {
          copyCacheToDir = join(
            appHomeDir.androidDir.path,
            'aar',
            'flutter',
          );
        } else {
          copyCacheToDir = join(
            appHomeDir.androidDir.path,
            'aar',
            'unity',
          );
        }
      }
    }

    if (!await metaxCache.isCacheExists(chooseCommitHash)) {
      throw '$chooseCommitHash 缓存Zip在本地不存在！';
    }

    await copyZipToDir(
      metaxCache.getZipCachePath(chooseCommitHash),
      Directory(copyCacheToDir),
    );

    final buildManager = BuildCacheManager(copyCacheToDir);
    await buildManager.appendCache(cacheModel);
    loggerSuccess('使用缓存成功!');
  }
}
