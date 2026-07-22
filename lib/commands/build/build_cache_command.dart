import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:meta_tool/cache/build_cache.dart';
import 'package:meta_tool/cache/cache_cleaner.dart';
import 'package:meta_tool/cache/cache_manager.dart';
import 'package:meta_tool/cache/cache_model.dart';
import 'package:meta_tool/cache/metax_cache.dart';
import 'package:meta_tool/common.dart';
import 'package:meta_tool/define.dart';
import 'package:meta_tool/upload_sentry.dart';
import 'package:path/path.dart';
import 'package:process_runner/process_runner.dart';

abstract class BuildCacheCommand extends Command {
  BuildCacheCommand() {
    argParser.addFlag(
      'isUpload',
      help: '是否上传缓存',
      defaultsTo: true,
    );
    argParser.addFlag(
      'forceUpdate',
      help: '强制更新缓存，清理现有缓存后重新构建',
      defaultsTo: false,
    );
  }

  late bool isUpload;
  late bool forceUpdate;

  @override
  FutureOr? run() async {
    isUpload = argResults?['isUpload'] ?? true;
    forceUpdate = argResults?['forceUpdate'] ?? false;
  }

  Future<void> updateCache({
    required MetaxCache cache,
    required String commitHash,
    required String buildCacheDir,
    required DateTime commitTime,
    required String cacheId,
    required bool forceUpdate,
    String flutterSdk = '',
  }) async {
    final cacheModel = await cache.getCacheModelFromCacheId(
      cacheId,
      flutterSdk: flutterSdk,
    );
    final startTime = DateTime.now();
    final buildModel = CacheModel(
      buildPlatform: cache.buildPlatform.value,
      buildLibrary: cache.buildLibrary.value,
      buildType: cache.buildType.value,
      branch: cache.branch,
      configuration: cache.buildConfiguration.value,
      commitHash: commitHash,
      buildId: cache.buildId.toString(),
      commitTime: commitTime,
      flutterSdk: flutterSdk,
    );

    if (forceUpdate) {
      loggerInfo('🔄 强制更新模式，清理现有缓存...');
      await cache.forceCleanCache();
    }

    final bool disableAllCache = !isLibraryCacheEnabled(cache.buildLibrary);
    if (disableAllCache) {
      // 全局 --no-isUseCache，或分库 --no-isUseFlutterCache / --no-isUseUnityCache：
      // 清理工程产物 + 宿主 frameworks/aar + ~/.metax，再强制全新编译
      final reason = !isUseCache
          ? '--no-isUseCache'
          : cache.buildLibrary == BuildLibrary.flutter
              ? '--no-isUseFlutterCache'
              : '--no-isUseUnityCache';
      loggerWarning('🧹 检测到 $reason，将强制全新编译，不使用任何本地缓存');

      await cleanCachesOnIgnore(
        appHomeDir: appHomeDir,
        library: cache.buildLibrary,
        metaxCache: cache,
      );

      // 避免 buildCacheDir 里的旧产物/旧 cache.json 被当成“最新编译”
      final buildDir = Directory(buildCacheDir);
      if (buildDir.existsSync()) {
        await buildDir.delete(recursive: true);
      }
    }

    if (!disableAllCache &&
        cacheModel != null &&
        await cache.isCacheExists(cacheModel.commitHash) &&
        !forceUpdate) {
      loggerWarning('🔍 本地缓存目录存在指定缓存，跳过编译......');
      commitHash = cacheModel.commitHash;
    } else if (!disableAllCache &&
        await isCacheExitsInBuildDir(buildModel, buildCacheDir) &&
        !forceUpdate) {
      loggerInfo('🔍 当前编译已经是最新的,正在复制到本地缓存目录......');

      await writeToCacheSystem(
        buildCacheDir: buildCacheDir,
        cache: cache,
        commitHash: commitHash,
        commitTime: commitTime,
        flutterSdk: flutterSdk,
      );
    } else {
      await buildCache();
      if (!Directory(buildCacheDir).existsSync()) {
        throw Exception('编译缓存目录不存在: $buildCacheDir');
      }
      await BuildCacheManager(buildCacheDir).write([
        CacheModel(
          buildPlatform: cache.buildPlatform.value,
          buildLibrary: cache.buildLibrary.value,
          buildType: cache.buildType.value,
          branch: cache.branch,
          configuration: cache.buildConfiguration.value,
          commitHash: commitHash,
          buildId: cache.buildId.toString(),
          commitTime: commitTime,
          flutterSdk: flutterSdk,
        ),
      ]);
      await writeToCacheSystem(
        buildCacheDir: buildCacheDir,
        cache: cache,
        commitHash: commitHash,
        commitTime: commitTime,
        flutterSdk: flutterSdk,
      );
      if (cache.buildPlatform == BuildPlatform.android) {
        // /Users/winner/Documents/meta_app_2.0/android/unityLibrary/symbols
        /// 分别上传到测试和生产环境
        await uploadAndroidUnitySymbols(true);
        await uploadAndroidUnitySymbols(false);
      }
    }
    final endTime = DateTime.now();
    loggerInfo('🔍 编译完成，用时: ${endTime.difference(startTime).inSeconds}秒');
  }

  Future<void> uploadAndroidUnitySymbols(bool isStore) async {
    final unitySymbolsPath = join(
      appHomeDir.androidDir.path,
      'unityLibrary',
      'symbols',
    );

    final sentryUrl =
        readBuildAppEnv('SENTRY_URL', appHomeDir, isStore: isStore);
    final sentryAuthToken =
        readBuildAppEnv('SENTRY_AUTH_TOKEN', appHomeDir, isStore: isStore);
    final sentryOrg =
        readBuildAppEnv('SENTRY_ORG', appHomeDir, isStore: isStore);
    final sentryProject =
        readBuildAppEnv('SENTRY_PROJECT', appHomeDir, isStore: isStore);

    await UploadAndroidSymbols(
      url: sentryUrl,
      authToken: sentryAuthToken,
      org: sentryOrg,
      project: sentryProject,
      symbolsPath: unitySymbolsPath,
    ).run().catchError((e, stackTrace) {
      loggerError('上传Android符号失败:${e.toString()} ${stackTrace.toString()}');
    });
  }

  /// 写入到缓存系统
  Future<void> writeToCacheSystem({
    required String buildCacheDir,
    required MetaxCache cache,
    required String commitHash,
    required DateTime commitTime,
    String flutterSdk = '',
  }) async {
    final buildCacheParentDir = Directory(buildCacheDir).parent;
    // final cacheBaseName = basename(buildCacheDir);

    String cacheId = commitHash;

    /// 压缩
    await ProcessRunner().runProcess(
      [
        'zip',
        "-r",
        join(buildCacheParentDir.path, '$cacheId.zip'),
        './',
      ],
      workingDirectory: Directory(buildCacheDir),
      printOutput: true,
    );

    final zipFile = File(join(buildCacheParentDir.path, '$cacheId.zip'));
    await cache.updateCacheData(
      zipFile,
      CacheModel(
        branch: cache.branch,
        commitHash: commitHash,
        buildId: cache.buildId.toString(),
        configuration: cache.buildConfiguration.value,
        buildPlatform: cache.buildPlatform.value,
        buildLibrary: cache.buildLibrary.value,
        buildType: cache.buildType.value,
        commitTime: commitTime,
        flutterSdk: flutterSdk,
      ),
    );
    await zipFile.delete();
  }

  Future<void> buildCache() async {}

  /// 当前编译目录是否存在缓存文件
  Future<bool> isCacheExitsInBuildDir(
      CacheModel buildModel, String buildCacheDir) async {
    final buildCache = BuildCache(buildCacheDir);
    final lastBuildConfig = await buildCache.getLastCacheConfig();
    if (lastBuildConfig == null) return false;
    return buildModel == lastBuildConfig;
  }
}
