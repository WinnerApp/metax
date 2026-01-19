import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:meta_tool/cache/cache_manager.dart';
import 'package:meta_tool/common.dart';
import 'package:meta_tool/define.dart';
import 'package:path/path.dart';

class CleanCacheCommand extends Command {
  @override
  String get description => '清理本地所有缓存';

  @override
  String get name => 'clean';

  CleanCacheCommand() {
    argParser.addFlag(
      'no-project',
      help: '不清理项目目录中的构建缓存，只清理全局缓存',
      defaultsTo: false,
    );
    argParser.addFlag(
      'dry-run',
      help: '仅显示将要清理的内容，不实际删除',
      defaultsTo: false,
    );
  }

  @override
  Future<void> run() async {
    final skipProject = argResults?['no-project'] ?? false;
    final dryRun = argResults?['dry-run'] ?? false;

    final metaxDir = Directory(join(readEnv(homeEnvName), '.metax'));
    loggerInfo('🧭 全局缓存目录: ${metaxDir.path}');
    loggerInfo('🧭 全局缓存索引: ${MetaxCacheManager().cacheFilePath}');

    // 统计全局缓存
    int globalCacheFileCount = 0;
    int globalTotalSize = 0;
    final List<File> globalCacheFiles = [];

    if (await metaxDir.exists()) {
      await for (final entity in metaxDir.list(recursive: true)) {
        if (entity is File && entity.path.endsWith('.zip')) {
          globalCacheFiles.add(entity);
          globalTotalSize += await entity.length();
        }
      }
      globalCacheFileCount = globalCacheFiles.length;
    }

    // 读取缓存元数据
    final cacheManager = MetaxCacheManager();
    final cacheModels = await cacheManager.read();
    final cacheModelCount = cacheModels.length;

    // 统计项目构建缓存（默认清理，除非指定 --no-project）
    int projectCacheCount = 0;
    final List<File> projectCacheFiles = [];
    if (!skipProject) {
      projectCacheFiles.addAll(await _findProjectCacheFiles());
      projectCacheCount = projectCacheFiles.length;
    }

    if (globalCacheFileCount == 0 &&
        cacheModelCount == 0 &&
        projectCacheCount == 0) {
      loggerInfo('没有找到缓存文件，无需清理');
      return;
    }

    // 显示清理信息
    loggerInfo('📦 全局缓存文件: $globalCacheFileCount 个');
    loggerInfo('📋 缓存元数据条目: $cacheModelCount 个');
    if (globalTotalSize > 0) {
      final sizeInMB = (globalTotalSize / (1024 * 1024)).toStringAsFixed(2);
      loggerInfo('💾 全局缓存总大小: $sizeInMB MB');
    }
    if (projectCacheCount > 0) {
      loggerInfo('📁 项目构建缓存文件: $projectCacheCount 个');
    }

    if (dryRun) {
      loggerInfo('🧪 dry-run 模式：仅展示统计信息，不执行删除');
      return;
    }

    // 清理全局缓存文件
    if (globalCacheFileCount > 0) {
      loggerInfo('🧹 开始清理全局缓存文件...');
      int deletedCount = 0;
      for (final file in globalCacheFiles) {
        try {
          await file.delete();
          deletedCount++;
        } catch (e) {
          loggerWarning('删除缓存文件失败: ${file.path}, 错误: $e');
        }
      }
      loggerInfo('✅ 已删除 $deletedCount 个全局缓存文件');
    }

    // 清理缓存元数据
    if (cacheModelCount > 0) {
      loggerInfo('🧹 开始清理缓存元数据...');
      try {
        await cacheManager.write([]);
        loggerInfo('✅ 已清空缓存元数据');
      } catch (e) {
        loggerWarning('清理缓存元数据失败: $e');
      }
    }

    // 清理项目构建缓存（默认清理，除非指定 --no-project）
    if (!skipProject && projectCacheCount > 0) {
      loggerInfo('🧹 开始清理项目构建缓存...');
      int deletedCount = 0;
      for (final file in projectCacheFiles) {
        try {
          await file.delete();
          deletedCount++;
        } catch (e) {
          loggerWarning('删除项目缓存文件失败: ${file.path}, 错误: $e');
        }
      }
      loggerInfo('✅ 已删除 $deletedCount 个项目构建缓存文件');
    }

    loggerSuccess('🎉 清理完成！');
  }

  /// 查找项目目录中的构建缓存文件
  Future<List<File>> _findProjectCacheFiles() async {
    final List<File> cacheFiles = [];

    try {
      // Flutter AAR 缓存
      final flutterHostCache =
          File(join(appHomeDir.workspace, 'build', 'host', 'cache.json'));
      if (await flutterHostCache.exists()) {
        cacheFiles.add(flutterHostCache);
      }

      // Unity Library iOS 缓存
      final iosUnityCache =
          File(join(appHomeDir.iosDir.path, 'UnityLibrary', 'cache.json'));
      if (await iosUnityCache.exists()) {
        cacheFiles.add(iosUnityCache);
      }

      // Unity Library Android 缓存
      final androidUnityCache =
          File(join(appHomeDir.androidDir.path, 'unityLibrary', 'cache.json'));
      if (await androidUnityCache.exists()) {
        cacheFiles.add(androidUnityCache);
      }

      // Unity AAR 构建缓存
      final unityAarCache = File(
          join(appHomeDir.workspace, 'build', 'unityLibrary', 'cache.json'));
      if (await unityAarCache.exists()) {
        cacheFiles.add(unityAarCache);
      }

      // Flutter Framework 缓存（Debug）
      final flutterFrameworkDebugCache = File(join(
        appHomeDir.flutterDir.path,
        'build',
        'ios',
        'framework',
        'Debug',
        'cache.json',
      ));
      if (await flutterFrameworkDebugCache.exists()) {
        cacheFiles.add(flutterFrameworkDebugCache);
      }

      // Flutter Framework 缓存（Release）
      final flutterFrameworkReleaseCache = File(join(
        appHomeDir.flutterDir.path,
        'build',
        'ios',
        'framework',
        'Release',
        'cache.json',
      ));
      if (await flutterFrameworkReleaseCache.exists()) {
        cacheFiles.add(flutterFrameworkReleaseCache);
      }
    } catch (e) {
      loggerWarning('查找项目缓存文件时出错: $e');
    }

    return cacheFiles;
  }
}
