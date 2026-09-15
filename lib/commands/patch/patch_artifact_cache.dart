import 'dart:io';

import 'package:meta_tool/cache/cache_manager.dart';
import 'package:meta_tool/cache/cache_model.dart';
import 'package:meta_tool/cache/framework_aar_cache.dart';
import 'package:meta_tool/cache/metax_cache.dart';
import 'package:meta_tool/commands/build/build_cache_command.dart';
import 'package:meta_tool/commands/build/framework/flutter_framework_command.dart';
import 'package:meta_tool/common.dart';
import 'package:meta_tool/define.dart';
import 'package:meta_tool/flutter_sdk.dart';
import 'package:meta_tool/flutterpatch.dart';
import 'package:path/path.dart';

/// 将 `flutterpatch patch` 生成的完整 aar / framework 按正常打包逻辑
/// 写入本地缓存，并按需上传到云端。
///
/// 不调用 [ensureFlutterSdkReady]：闸门在 SDK 变化时会 `flutter clean`，
/// 会删掉刚打出来的补丁产物。此处只解析指纹，与打包缓存命中键一致。
Future<void> cacheAndUploadFlutterPatchArtifacts({
  required Directory flutterDir,
  required String otaPlatform,
  required String releaseVersion,
  required bool isUpload,
}) async {
  await ensureFvmFlutterReady(flutterDir);
  final sdk = await resolveFlutterSdk(flutterDir);
  final sdkFingerprint = shorebirdSdkFingerprint(sdk.fingerprint);
  await saveFlutterSdkFingerprint(projectPath: flutterDir.path, sdk: sdk);

  final branch = await getCurrentBranch(flutterDir.path);
  final commitHash = await getCurrentCommitHash(flutterDir.path);
  final commitTime = await getCommitTime(flutterDir.path, commitHash);

  final target = resolveFlutterPatchArtifactCacheTarget(
    flutterDir: flutterDir,
    otaPlatform: otaPlatform,
    branch: branch,
  );

  loggerInfo(
    '同步补丁完整产物到打包目录: ${target.buildCacheDir} '
    '(${target.buildType.value}, commit=$commitHash)',
  );

  if (target.buildType == BuildType.aar) {
    await syncFlutterPatchAarReleaseToHostDir(flutterDir);
  } else {
    await syncFlutterPatchIosReleaseToFrameworkDir(flutterDir);
    await runSetupIosFrameworkPodspec(
      configurationDirName: 'Release',
      frameworkOutputDir: target.buildCacheDir,
    );
  }

  if (!Directory(target.buildCacheDir).existsSync()) {
    throw Exception('补丁产物目录不存在: ${target.buildCacheDir}');
  }

  await BuildCacheManager(target.buildCacheDir).write([
    CacheModel(
      buildPlatform: target.buildPlatform.value,
      buildLibrary: BuildLibrary.flutter.value,
      buildType: target.buildType.value,
      branch: branch,
      configuration: BuildConfiguration.release.value,
      commitHash: commitHash,
      buildId: '0',
      commitTime: commitTime,
      flutterSdk: sdkFingerprint,
      isShorebird: true,
      releaseVersion: releaseVersion,
    ),
  ]);

  loggerInfo('写入本地 Flutter ${target.buildType.value} 缓存...');
  await writeBuildDirToCacheSystem(
    buildCacheDir: target.buildCacheDir,
    cache: target.cache,
    commitHash: commitHash,
    commitTime: commitTime,
    flutterSdk: sdkFingerprint,
    isShorebird: true,
    releaseVersion: releaseVersion,
  );

  if (!isUpload) {
    loggerInfo('已跳过上传缓存（--no-isUpload）');
    return;
  }

  loggerDebug('上传 Flutter ${target.buildType.value} 缓存到云服务器...');
  await uploadCacheResource(
    buildPlatform: target.buildPlatform,
    buildLibrary: BuildLibrary.flutter,
    buildConfiguration: BuildConfiguration.release,
    buildType: target.buildType,
    branch: branch,
    commitHash: commitHash,
    commitTime: commitTime,
    buildId: 0,
  );
}

/// 补丁产物与 `metax build aar/framework flutter` 使用同一套目录与缓存键。
({
  String buildCacheDir,
  BuildPlatform buildPlatform,
  BuildType buildType,
  MetaxCache cache,
}) resolveFlutterPatchArtifactCacheTarget({
  required Directory flutterDir,
  required String otaPlatform,
  required String branch,
}) {
  switch (otaPlatform) {
    case 'android':
      return (
        buildCacheDir: join(flutterDir.path, 'build', 'host'),
        buildPlatform: BuildPlatform.android,
        buildType: BuildType.aar,
        cache: AarCache(
          branch: branch,
          buildConfiguration: BuildConfiguration.release,
          buildLibrary: BuildLibrary.flutter,
          buildId: 0,
        ),
      );
    case 'ios':
      return (
        buildCacheDir: join(
          flutterDir.path,
          'build',
          'ios',
          'framework',
          'Release',
        ),
        buildPlatform: BuildPlatform.ios,
        buildType: BuildType.framework,
        cache: FrameworkCache(
          branch: branch,
          buildConfiguration: BuildConfiguration.release,
          buildLibrary: BuildLibrary.flutter,
          buildId: 0,
        ),
      );
    default:
      throw Exception('不支持的热更平台: $otaPlatform（仅 android | ios）');
  }
}
