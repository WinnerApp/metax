import 'dart:async';

import 'package:args/command_runner.dart';
import 'package:meta_tool/argument_get.dart';
import 'package:meta_tool/cache/cache_manager.dart';
import 'package:meta_tool/cache/cache_model.dart';
import 'package:meta_tool/commands/cache/use_local_cache_mixin.dart';
import 'package:meta_tool/common.dart';
import 'package:meta_tool/define.dart';
import 'package:prompts/prompts.dart' as prompts;

class UseLocalCacheCommand extends Command with UseLocalCacheMixin {
  @override
  String get description => '使用本地缓存';

  @override
  String get name => 'use-local-cache';

  UseLocalCacheCommand() {
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
  }

  @override
  FutureOr? run() async {
    final buildPlatform = ArgumentGet(argResults).getString(
      'buildPlatform',
      '请选择构建平台',
      allowed: BuildPlatform.values.map((e) => e.name).toList(),
    );
    if (buildPlatform == BuildPlatform.ios.name &&
        !appHomeDir.iosDir.existsSync()) {
      throw Exception('目录[${appHomeDir.iosDir.path}]不存在,无法初始化缓存！');
    }
    if (buildPlatform == BuildPlatform.android.name &&
        !appHomeDir.androidDir.existsSync()) {
      throw Exception('目录[${appHomeDir.androidDir.path}]不存在,无法初始化缓存！');
    }

    final buildLibrary = ArgumentGet(argResults).getString(
      'buildLibrary',
      '请选择构建库',
      allowed: BuildLibrary.values.map((e) => e.name).toList(),
    );
    String buildConfiguration = switch (buildLibrary) {
      'flutter' => ArgumentGet(argResults).getString(
          'buildConfiguration',
          '请选择构建配置',
          allowed: BuildConfiguration.values.map((e) => e.name).toList(),
        ),
      _ => BuildConfiguration.release.name,
    };

    late String buildType;
    if (buildPlatform == BuildPlatform.ios.name) {
      if (buildLibrary == BuildLibrary.flutter.name) {
        buildType = BuildType.framework.value;
      } else {
        buildType = ArgumentGet(argResults).getString(
          'buildType',
          '请选择构建类型',
          allowed: [
            BuildType.framework.value,
            BuildType.library.value,
          ],
        );
      }
    } else {
      if (buildLibrary == BuildLibrary.flutter.name) {
        buildType = BuildType.aar.value;
      } else {
        buildType = ArgumentGet(argResults).getString(
          'buildType',
          '请选择构建类型',
          allowed: [
            BuildType.aar.value,
            BuildType.library.value,
          ],
        );
      }
    }

    /// 查询当前本地存在的缓存
    final cacheManager = MetaxCacheManager();
    List<CacheModel> cacheModels = await cacheManager.read();
    cacheModels = cacheModels
        .where((e) => e.buildPlatform == buildPlatform)
        .where((e) => e.buildLibrary == buildLibrary)
        .where((e) => e.buildType == buildType)
        .where((e) => e.configuration == buildConfiguration)
        .toList();

    if (cacheModels.isEmpty) {
      throw Exception('本地不存在该配置的缓存！');
    }

    final branchs = cacheModels.map((e) => e.branch).toSet().toList();
    final branch = prompts.choose('请选择分支:', branchs);
    cacheModels = cacheModels.where((e) => e.branch == branch).toList();

    if (cacheModels.isEmpty) {
      throw Exception('本地不存在该配置的缓存！');
    }

    final buildVersions =
        cacheModels.map((e) => int.parse(e.buildId)).toSet().toList();
    buildVersions.sort((a, b) => b.compareTo(a));
    if (buildVersions.length > 1) {
      final buildId = prompts.choose('请选择版本:', buildVersions);
      cacheModels =
          cacheModels.where((e) => e.buildId == buildId.toString()).toList();
    }
    if (cacheModels.isEmpty) {
      throw Exception('本地不存在该配置的缓存');
    }

    final cacheModel = cacheModels.last;

    await useLocalCache(
      cacheModel: cacheModel,
      appHomeDir: appHomeDir,
      buildPlatform: buildPlatform,
      buildLibrary: buildLibrary,
      buildConfiguration: buildConfiguration,
      buildType: buildType,
    );
    loggerSuccess('使用本地缓存成功！');
  }
}
