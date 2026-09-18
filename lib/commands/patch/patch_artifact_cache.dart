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

/// 将 `flutterpatch patch` 生成的完整 aar / framework 写入本地 **patched** 槽。
///
/// 不会覆盖同 commit 的 release 基线缓存；也不上传到与 release 共享的云端缓存键，
/// 避免后续 `--from-release` / 下载复用拿到补丁全量包。
///
/// 不调用 [ensureFlutterSdkReady]：闸门在 SDK 变化时会 `flutter clean`，
/// 会删掉刚打出来的补丁产物。此处只解析指纹，与打包缓存命中键一致。
Future<void> cacheAndUploadFlutterPatchArtifacts({
  required Directory flutterDir,
  required String otaPlatform,
  required String releaseVersion,
  required bool isUpload,
  int? sourcePatchNumber,
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
    '(${target.buildType.value}, commit=$commitHash, slot=patched'
    '${sourcePatchNumber != null ? ', patch=#$sourcePatchNumber' : ''})',
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

  final packageHash = await hashFlutterPatchPackageArtifact(
    buildCacheDir: Directory(target.buildCacheDir),
    buildType: target.buildType,
  );

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
      artifactKind: CacheArtifactKind.patched,
      contentHash: packageHash ?? '',
      sourcePatchNumber: sourcePatchNumber,
    ),
  ]);

  loggerInfo('写入本地 Flutter ${target.buildType.value} patched 缓存（不覆盖 release 槽）...');
  await writeBuildDirToCacheSystem(
    buildCacheDir: target.buildCacheDir,
    cache: target.cache,
    commitHash: commitHash,
    commitTime: commitTime,
    flutterSdk: sdkFingerprint,
    isShorebird: true,
    releaseVersion: releaseVersion,
    artifactKind: CacheArtifactKind.patched,
    contentHashOverride: packageHash,
    sourcePatchNumber: sourcePatchNumber,
  );

  if (isUpload) {
    loggerInfo(
      '已跳过上传补丁全量包到共享 release 云缓存'
      '（仅本地 patched 槽；带热更发新宿主请 promote 为新 release 基线）',
    );
  } else {
    loggerInfo('已跳过上传缓存（--no-isUpload）');
  }
}

/// 补丁产物与 `metax build aar/framework flutter` 使用同一套目录；
/// 本地 zip 槽位为 [CacheArtifactKind.patched]，与 release 并存。
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
