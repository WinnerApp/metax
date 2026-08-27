import 'dart:io';

import 'package:meta_tool/app_home_dir.dart';
import 'package:meta_tool/cache/cache_model.dart';
import 'package:meta_tool/cache/metax_cache.dart';
import 'package:meta_tool/common.dart';
import 'package:meta_tool/define.dart';
import 'package:path/path.dart';

mixin UseLocalCacheMixin {
  /// 使用缓存
  Future<void> useLocalCache({
    required CacheModel cacheModel,
    required AppHomeDir appHomeDir,
    required String buildPlatform,
    required String buildLibrary,
    required String buildType,
    required String buildConfiguration,
  }) async {
    final targetDir = Directory(
      getBinaryCachePath(
        appHomeDir: appHomeDir,
        buildPlatform: buildPlatform,
        buildLibrary: buildLibrary,
        buildType: buildType,
        buildConfiguration: buildConfiguration,
      ),
    );
    final metaxCache = createMetaxCache(
      buildId: int.parse(cacheModel.buildId),
      buildPlatform: buildPlatform,
      buildLibrary: buildLibrary,
      buildType: buildType,
      buildConfiguration: buildConfiguration,
      branch: cacheModel.branch,
    );
    final zipPath = metaxCache.getZipCachePath(cacheModel.commitHash);
    await copyZipToDir(zipPath, targetDir);

    /// 如果当前是iOS 并且是Flutter则需要复制隐私文件到对应目录
    if (buildPlatform == BuildPlatform.ios.name &&
        buildLibrary == BuildLibrary.flutter.name &&
        buildType == BuildType.framework.name) {
      final privacyDir = Directory(join(
        appHomeDir.iosDir.path,
        'frameworks',
        'Privacys',
      ));
      final targetPrivacyDir = Directory(join(
        appHomeDir.iosDir.path,
        'frameworks',
        'flutter',
        buildConfiguration == BuildConfiguration.release.name
            ? 'Release'
            : 'Debug',
        'Privacys',
      ));
      if (await targetPrivacyDir.exists()) {
        await targetPrivacyDir.delete(recursive: true);
      }
      await copyDirToDir(privacyDir, targetPrivacyDir);

      await alignIosFlutterFrameworkPodspecs(
        appHomeDir: appHomeDir,
        buildConfiguration: buildConfiguration,
      );
    }
  }

  /// 获取二进制缓存存放的路径
  String getBinaryCachePath({
    required AppHomeDir appHomeDir,
    required String buildPlatform,
    required String buildLibrary,
    required String buildType,
    required String buildConfiguration,
  }) {
    if (buildPlatform == BuildPlatform.ios.name) {
      if (buildType == BuildType.library.name) {
        return join(appHomeDir.iosDir.path, 'UnityLibrary');
      } else if (buildType == BuildType.framework.name) {
        if (buildLibrary == BuildLibrary.unity.name) {
          return join(appHomeDir.iosDir.path, 'frameworks', 'unity');
        } else if (buildLibrary == BuildLibrary.flutter.name) {
          if (buildConfiguration == BuildConfiguration.release.name) {
            return join(
                appHomeDir.iosDir.path, 'frameworks', 'flutter', 'Release');
          } else if (buildConfiguration == BuildConfiguration.debug.name) {
            return join(
                appHomeDir.iosDir.path, 'frameworks', 'flutter', 'Debug');
          } else {
            throw Exception('不支持的构建配置: $buildConfiguration');
          }
        } else {
          throw Exception('不支持的构建库: $buildLibrary');
        }
      } else {
        throw Exception('不支持的构建类型: $buildType');
      }
    } else if (buildPlatform == BuildPlatform.android.name) {
      if (buildType == BuildType.library.name) {
        return join(appHomeDir.androidDir.path, 'unityLibrary');
      } else if (buildType == BuildType.aar.name) {
        if (buildLibrary == BuildLibrary.unity.name) {
          return join(appHomeDir.androidDir.path, 'aar', 'unity');
        } else if (buildLibrary == BuildLibrary.flutter.name) {
          return join(appHomeDir.androidDir.path, 'aar', 'flutter');
        } else {
          throw Exception('不支持的构建库: $buildLibrary');
        }
      } else {
        throw Exception('不支持的构建类型: $buildType');
      }
    } else if (buildPlatform == BuildPlatform.ohos.name) {
      if (buildType == BuildType.library.name) {
        return join(appHomeDir.ohosDir.path, 'unityLibrary');
      } else if (buildType == BuildType.har.name) {
        if (buildLibrary == BuildLibrary.flutter.name) {
          final mode =
              buildConfiguration == BuildConfiguration.debug.name
                  ? 'debug'
                  : 'release';
          return join(appHomeDir.ohosDir.path, 'aar', 'flutter', mode);
        } else if (buildLibrary == BuildLibrary.unity.name) {
          return join(appHomeDir.ohosDir.path, 'aar', 'unity');
        }
        throw Exception('不支持的构建库: $buildLibrary');
      } else {
        throw Exception('ohos仅支持 library/har 构建类型: $buildType');
      }
    } else {
      throw Exception('不支持的平台: $buildPlatform');
    }
  }

  /// 根据buildId创建MetaxCache
  MetaxCache createMetaxCache({
    required int buildId,
    required String buildPlatform,
    required String buildLibrary,
    required String buildType,
    required String buildConfiguration,
    required String branch,
  }) {
    return MetaxCache(
      buildPlatform: BuildPlatform.values.firstWhere(
        (e) => e.name == buildPlatform,
      ),
      buildConfiguration: BuildConfiguration.values.firstWhere(
        (e) => e.name == buildConfiguration,
      ),
      buildLibrary: BuildLibrary.values.firstWhere(
        (e) => e.name == buildLibrary,
      ),
      buildType: BuildType.values.firstWhere(
        (e) => e.name == buildType,
      ),
      branch: branch,
      buildId: buildId,
    );
  }
}
