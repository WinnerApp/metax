import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:crypto/crypto.dart';
import 'package:meta_tool/cache/build_cache.dart';
import 'package:meta_tool/cache/cache_cleaner.dart';
import 'package:meta_tool/cache/cache_manager.dart';
import 'package:meta_tool/cache/cache_model.dart';
import 'package:meta_tool/cache/metax_cache.dart';
import 'package:meta_tool/common.dart';
import 'package:meta_tool/define.dart';
import 'package:meta_tool/flutterpatch.dart';
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
    bool isShorebird = false,
    String releaseVersion = '',
  }) async {
    final cacheModel = await cache.getCacheModelFromCacheId(
      cacheId,
      flutterSdk: flutterSdk,
      isShorebird: isShorebird,
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
      isShorebird: isShorebird,
      releaseVersion: releaseVersion,
      artifactKind: CacheArtifactKind.release,
    );

    if (forceUpdate) {
      loggerInfo('🔄 强制更新模式，清理现有缓存...');
      await cache.forceCleanCache();
    }

    final bool disableAllCache = !isLibraryCacheEnabled(cache.buildLibrary);
    if (disableAllCache) {
      // 全局 --no-isUseCache，或分库 --no-isUseFlutterCache / --no-isUseUnityCache：
      // 仅清理当前库的工程产物 + 宿主 frameworks/aar + ~/.metax，再强制全新编译
      final reason = !isUseCache
          ? '--no-isUseCache（仅 ${cache.buildLibrary.name}）'
          : cache.buildLibrary == BuildLibrary.flutter
              ? '--no-isUseFlutterCache'
              : '--no-isUseUnityCache';
      loggerWarning('🧹 检测到 $reason，将强制全新编译，不使用该库本地缓存');

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
        cacheModel.artifactKind == CacheArtifactKind.release &&
        await cache.isCacheExists(
          cacheModel.commitHash,
          artifactKind: CacheArtifactKind.release,
        ) &&
        !forceUpdate) {
      loggerWarning('🔍 本地缓存目录存在指定缓存，跳过编译......');
      commitHash = cacheModel.commitHash;
      await _cloneFlutterPatchReleaseIfNeeded(
        cache: cache,
        cached: cacheModel,
        releaseVersion: releaseVersion,
      );
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
        isShorebird: isShorebird,
        releaseVersion: releaseVersion,
        artifactKind: CacheArtifactKind.release,
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
          isShorebird: isShorebird,
          releaseVersion: releaseVersion,
          artifactKind: CacheArtifactKind.release,
        ),
      ]);
      await writeToCacheSystem(
        buildCacheDir: buildCacheDir,
        cache: cache,
        commitHash: commitHash,
        commitTime: commitTime,
        flutterSdk: flutterSdk,
        isShorebird: isShorebird,
        releaseVersion: releaseVersion,
        artifactKind: CacheArtifactKind.release,
      );
      if (cache.buildPlatform == BuildPlatform.android) {
        // android/unityLibrary/symbols
        /// 分别上传到测试和生产环境
        await uploadAndroidUnitySymbols(true);
        await uploadAndroidUnitySymbols(false);
      }
    }
    final endTime = DateTime.now();
    loggerInfo('🔍 编译完成，用时: ${endTime.difference(startTime).inSeconds}秒');
  }

  /// FlutterPatch Flutter framework/aar 缓存命中时，按需 `--from-release`。
  Future<void> _cloneFlutterPatchReleaseIfNeeded({
    required MetaxCache cache,
    required CacheModel cached,
    required String releaseVersion,
  }) async {
    if (!cached.isShorebird &&
        !isShorebirdSdkFingerprint(cached.flutterSdk)) {
      return;
    }
    if (cache.buildLibrary != BuildLibrary.flutter) return;
    final platform = switch (cache.buildPlatform) {
      BuildPlatform.ios when cache.buildType == BuildType.framework =>
        'ios-framework',
      BuildPlatform.android when cache.buildType == BuildType.aar => 'aar',
      _ => null,
    };
    if (platform == null) return;

    final current = releaseVersion.trim().isNotEmpty
        ? releaseVersion.trim()
        : (resolveReleaseVersionFromEnv() ?? '');
    final cloned = await maybeCloneFlutterPatchReleaseFromCache(
      flutterDir: appHomeDir.flutterDir,
      platform: platform,
      releaseVersion: current,
      cachedReleaseVersion: cached.releaseVersion,
      artifactKind: cached.artifactKind,
      contentHash: cached.contentHash,
      sourcePatchNumber: cached.sourcePatchNumber,
    );
    if (!cloned) return;

    // 索引记为当前宿主版本，方便下次链式 from-release。
    // patched promote 成功后视为新 release 基线（OTA 已登记 origin=release）。
    final infos = [...await cache.cacheManager.read()];
    final index = infos.indexWhere((e) => e == cached);
    if (index != -1) {
      infos[index] = infos[index].copyWith(
        releaseVersion: current,
        artifactKind: CacheArtifactKind.release,
        clearSourcePatchNumber: true,
      );
      await cache.cacheManager.write(infos);
    }
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
    bool isShorebird = false,
    String releaseVersion = '',
    CacheArtifactKind artifactKind = CacheArtifactKind.release,
  }) {
    return writeBuildDirToCacheSystem(
      buildCacheDir: buildCacheDir,
      cache: cache,
      commitHash: commitHash,
      commitTime: commitTime,
      flutterSdk: flutterSdk,
      isShorebird: isShorebird,
      releaseVersion: releaseVersion,
      artifactKind: artifactKind,
    );
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

/// 将产物目录打成 zip 并写入 `~/.metax` 本地缓存索引（按 [artifactKind] 分槽）。
Future<void> writeBuildDirToCacheSystem({
  required String buildCacheDir,
  required MetaxCache cache,
  required String commitHash,
  required DateTime commitTime,
  String flutterSdk = '',
  bool isShorebird = false,
  String releaseVersion = '',
  CacheArtifactKind artifactKind = CacheArtifactKind.release,
  String? contentHashOverride,
  int? sourcePatchNumber,
}) async {
  final buildCacheParentDir = Directory(buildCacheDir).parent;
  final stagingZipName = '$commitHash.${artifactKind.name}.staging.zip';
  final stagingZipPath = join(buildCacheParentDir.path, stagingZipName);

  await ProcessRunner().runProcess(
    [
      'zip',
      '-r',
      stagingZipPath,
      './',
    ],
    workingDirectory: Directory(buildCacheDir),
    printOutput: true,
  );

  final zipFile = File(stagingZipPath);
  final zipHash = (await sha256.bind(zipFile.openRead()).first).toString();
  var contentHash = (contentHashOverride ?? '').trim();
  if (contentHash.isEmpty && isShorebird) {
    contentHash = (await hashFlutterPatchPackageArtifact(
          buildCacheDir: Directory(buildCacheDir),
          buildType: cache.buildType,
        ))
            ?.trim() ??
        '';
  }
  if (contentHash.isEmpty) {
    contentHash = zipHash;
  }
  loggerInfo(
    '写入本地缓存槽 ${artifactKind.name}: commit=$commitHash '
    'sha256=${contentHash.substring(0, 12)}…'
    '${sourcePatchNumber != null ? ' patch=#$sourcePatchNumber' : ''}',
  );
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
      isShorebird: isShorebird,
      releaseVersion: releaseVersion,
      artifactKind: artifactKind,
      contentHash: contentHash,
      sourcePatchNumber: sourcePatchNumber,
    ),
  );
  await zipFile.delete();
}
