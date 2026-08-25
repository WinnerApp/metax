import 'dart:io';

import 'package:meta_tool/app_home_dir.dart';
import 'package:meta_tool/cache/cache_manager.dart';
import 'package:meta_tool/cache/metax_cache.dart';
import 'package:meta_tool/common.dart';
import 'package:meta_tool/define.dart';
import 'package:path/path.dart';

/// 忽略缓存时，只清理「当前正在处理的库」的工程产物与 ~/.metax 缓存。
///
/// 即使是全局 `--no-isUseCache`，也只清 [library]，避免 Flutter 阶段误删已落地的 Unity 产物（或反之）。
Future<void> cleanCachesOnIgnore({
  required AppHomeDir appHomeDir,
  required BuildLibrary library,
  MetaxCache? metaxCache,
}) async {
  final reason = !isUseCache
      ? '全局 --no-isUseCache，仅清理 ${library.name}'
      : library == BuildLibrary.flutter
          ? '--no-isUseFlutterCache'
          : '--no-isUseUnityCache';

  loggerWarning('🧹 忽略缓存，开始清理本地产物（$reason）...');

  await cleanLibraryCaches(appHomeDir: appHomeDir, library: library);

  // 当前这次打包对应的 metax 子目录再清一遍（兼容旧 zip 残留）
  if (metaxCache != null) {
    await metaxCache.forceCleanCache();
  }

  loggerSuccess('🧹 忽略缓存相关目录清理完成');
}

/// 手动清理指定库的工程产物与 ~/.metax 缓存。
Future<void> cleanLibraryCaches({
  required AppHomeDir appHomeDir,
  required BuildLibrary library,
}) async {
  loggerInfo('🧹 开始清理 ${library.name} 相关缓存...');

  if (library == BuildLibrary.flutter) {
    await cleanFlutterModuleCaches(appHomeDir);
    await cleanFlutterHostCaches(appHomeDir);
    await cleanMetaxLibraryCaches(BuildLibrary.flutter);
  } else {
    await cleanUnityHostCaches(appHomeDir);
    await cleanMetaxLibraryCaches(BuildLibrary.unity);
  }

  loggerSuccess('🧹 ${library.name} 缓存清理完成');
}

/// 手动清理 Flutter 与 Unity 的全部工程产物与 ~/.metax 缓存。
Future<void> cleanAllLibraryCaches({
  required AppHomeDir appHomeDir,
}) async {
  loggerInfo('🧹 开始清理 Flutter 与 Unity 相关缓存...');

  await cleanFlutterModuleCaches(appHomeDir);
  await cleanFlutterHostCaches(appHomeDir);
  await cleanUnityHostCaches(appHomeDir);
  await cleanMetaxLibraryCaches(BuildLibrary.flutter);
  await cleanMetaxLibraryCaches(BuildLibrary.unity);

  loggerSuccess('🧹 全部缓存清理完成');
}

Future<void> deleteDirIfExists(Directory dir) async {
  if (await dir.exists()) {
    await dir.delete(recursive: true);
    loggerDebug('已删除目录: ${dir.path}');
  }
}

Future<void> deleteFileIfExists(File file) async {
  if (await file.exists()) {
    await file.delete();
    loggerDebug('已删除文件: ${file.path}');
  }
}

/// metaapp_flutter 工程内缓存
Future<void> cleanFlutterModuleCaches(AppHomeDir appHomeDir) async {
  final flutterDir = appHomeDir.flutterDir;
  if (!await flutterDir.exists()) return;

  await deleteDirIfExists(Directory(join(flutterDir.path, 'build')));
  await deleteDirIfExists(Directory(join(flutterDir.path, '.dart_tool')));
  await deleteDirIfExists(Directory(join(flutterDir.path, '.ios', 'Pods')));
  await deleteDirIfExists(Directory(join(flutterDir.path, '.ios', '.symlinks')));
  await deleteDirIfExists(Directory(join(flutterDir.path, '.android')));
  await deleteDirIfExists(Directory(join(flutterDir.path, '.ohos', 'har')));
  await deleteFileIfExists(
    File(join(flutterDir.path, '.ios', 'Podfile.lock')),
  );
}

/// iOS / Android / 鸿蒙宿主侧 Flutter 产物缓存
Future<void> cleanFlutterHostCaches(AppHomeDir appHomeDir) async {
  if (await appHomeDir.iosDir.exists()) {
    await deleteDirIfExists(
      Directory(join(appHomeDir.iosDir.path, 'frameworks', 'flutter')),
    );
    await deleteDirIfExists(
      Directory(join(appHomeDir.iosDir.path, 'build')),
    );
  }
  if (await appHomeDir.androidDir.exists()) {
    await deleteDirIfExists(
      Directory(join(appHomeDir.androidDir.path, 'aar', 'flutter')),
    );
  }
  if (await appHomeDir.ohosDir.exists()) {
    await deleteDirIfExists(
      Directory(join(appHomeDir.ohosDir.path, 'aar', 'flutter')),
    );
  }
}

/// iOS / Android 宿主侧 Unity 产物缓存（不删 Unity 工程源码目录本身）
Future<void> cleanUnityHostCaches(AppHomeDir appHomeDir) async {
  if (await appHomeDir.iosDir.exists()) {
    await deleteDirIfExists(
      Directory(join(appHomeDir.iosDir.path, 'frameworks', 'unity')),
    );
    await deleteDirIfExists(
      Directory(join(appHomeDir.iosDir.path, 'UnityLibrary', 'build')),
    );
    await deleteDirIfExists(
      Directory(join(appHomeDir.iosDir.path, 'build')),
    );
  }
  if (await appHomeDir.androidDir.exists()) {
    await deleteDirIfExists(
      Directory(join(appHomeDir.androidDir.path, 'aar', 'unity')),
    );
    await deleteDirIfExists(
      Directory(join(
        appHomeDir.workspace,
        'build',
        'unityLibrary',
        'outputs',
        'aar',
      )),
    );
  }
  if (await appHomeDir.unityAndroidDir.exists()) {
    await deleteDirIfExists(
      Directory(join(
        appHomeDir.unityAndroidDir.path,
        'unityLibrary',
        'build',
      )),
    );
  }
  if (await appHomeDir.ohosDir.exists()) {
    await deleteDirIfExists(
      Directory(join(appHomeDir.ohosDir.path, 'aar', 'unity')),
    );
  }
  await deleteDirIfExists(
    Directory(join(appHomeDir.workspace, 'build', 'unityLibrary')),
  );
}

/// 清理 ~/.metax 下指定 library 的全部平台/配置/分支缓存，并更新索引
Future<void> cleanMetaxLibraryCaches(BuildLibrary library) async {
  final metaxRoot = Directory(join(readEnv('HOME'), '.metax'));
  if (!await metaxRoot.exists()) return;

  // ~/.metax/{platform}/{configuration}/{library}/...
  await for (final platformEntity in metaxRoot.list()) {
    if (platformEntity is! Directory) continue;
    final platformName = basename(platformEntity.path);
    if (platformName == 'flutter_sdk') continue;

    await for (final configEntity in platformEntity.list()) {
      if (configEntity is! Directory) continue;
      final libraryDir = Directory(join(configEntity.path, library.name));
      if (await libraryDir.exists()) {
        await libraryDir.delete(recursive: true);
        loggerDebug('已删除 metax 缓存: ${libraryDir.path}');
      }
    }
  }

  final manager = MetaxCacheManager();
  final allModels = await manager.read();
  final filtered = allModels
      .where((model) => model.buildLibrary != library.name)
      .toList();
  if (filtered.length != allModels.length) {
    await manager.write(filtered);
    loggerDebug(
      '已从 ~/.metax/cache.json 移除 ${allModels.length - filtered.length} 条 ${library.name} 索引',
    );
  }
}
