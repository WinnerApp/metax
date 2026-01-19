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
      'confirm',
      help: '确认清理，跳过交互式确认',
      defaultsTo: false,
    );
  }

  @override
  Future<void> run() async {
    final confirm = argResults?['confirm'] ?? false;

    final metaxDir = Directory(join(readEnv(homeEnvName), '.metax'));

    if (!await metaxDir.exists()) {
      loggerInfo('缓存目录不存在，无需清理');
      return;
    }

    // 读取缓存元数据
    final cacheManager = MetaxCacheManager();
    final cacheModels = await cacheManager.read();
    final cacheModelCount = cacheModels.length;

    // 统计并收集缓存文件
    final List<File> cacheFiles = [];
    int totalSize = 0;

    await for (final entity in metaxDir.list(recursive: true)) {
      if (entity is File && entity.path.endsWith('.zip')) {
        cacheFiles.add(entity);
        totalSize += await entity.length();
      }
    }

    final cacheFileCount = cacheFiles.length;

    if (cacheFileCount == 0 && cacheModelCount == 0) {
      loggerInfo('没有找到缓存文件，无需清理');
      return;
    }

    // 显示清理信息
    loggerInfo('📦 找到缓存文件: $cacheFileCount 个');
    loggerInfo('📋 缓存元数据条目: $cacheModelCount 个');
    if (totalSize > 0) {
      final sizeInMB = (totalSize / (1024 * 1024)).toStringAsFixed(2);
      loggerInfo('💾 总大小: $sizeInMB MB');
    }

    // 确认清理
    if (!confirm) {
      loggerWarning('⚠️  即将清理所有本地缓存，此操作不可恢复！');
      loggerInfo('如需确认清理，请使用 --confirm 参数');
      return;
    }

    // 清理缓存文件
    loggerInfo('🧹 开始清理缓存文件...');
    int deletedCount = 0;
    for (final file in cacheFiles) {
      try {
        await file.delete();
        deletedCount++;
      } catch (e) {
        loggerWarning('删除缓存文件失败: ${file.path}, 错误: $e');
      }
    }
    loggerInfo('✅ 已删除 $deletedCount 个缓存文件');

    // 清理缓存元数据
    loggerInfo('🧹 开始清理缓存元数据...');
    try {
      await cacheManager.write([]);
      loggerInfo('✅ 已清空缓存元数据');
    } catch (e) {
      loggerWarning('清理缓存元数据失败: $e');
    }

    loggerSuccess('🎉 清理完成！');
  }
}
