import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:meta_tool/appwrite_server.dart';
import 'package:meta_tool/cache/framework_aar_cache.dart';
import 'package:meta_tool/cache/unity_cache.dart';
import 'package:meta_tool/commands/upload/upload_app_environment.dart';
import 'package:meta_tool/common.dart';
import 'package:path/path.dart';

abstract class UploadAppCommand extends Command {
  final UploadAppEnvironment environment;
  UnityCache get unityCache;
  FrameworkAarCache get flutterFrameworkAarCache;
  FrameworkAarCache get unityFrameworkAarCache;
  Directory get unityProjectDir;
  Directory get unityFrameworkAarDir;
  Directory get flutterFrameworkAarDir;
  Directory get flutterProjectDir =>
      Directory(join(environment.workspace, 'metaapp_flutter'));
  Directory get iosProjectDir => Directory(join(environment.workspace, 'ios'));
  Directory get androidProjectDir =>
      Directory(join(environment.workspace, 'android'));

  late AppwriteServer appwriteServer;

  UploadAppCommand({required this.environment}) {
    appwriteServer = AppwriteServer(
      endpoint: environment.appwriteEndpoint,
      projectId: environment.appwriteProjectId,
      apiKey: environment.appwriteApiKey,
    );
  }

  @override
  FutureOr? run() async {
    if (!flutterProjectDir.existsSync() &&
        !iosProjectDir.existsSync() &&
        !androidProjectDir.existsSync()) {
      throw Exception('打包目录不正确！打包目录需要包含ios、android、metaapp_flutter目录');
    }

    /// 查询最新的打包版本配置
    final config = await appwriteServer.getCurrentBranchBuildConfig(
      databaseId: environment.appwriteDatabaseId,
      collectionId: environment.appwriteCollectionId,
      platform: environment.platform,
      branch: environment.branch,
      unityBranch: environment.unityBranchName,
      buildName: environment.buildName,
    );

    /// 上一次Flutter打包Commit id
    String? flutterCommitId = config?['flutter_commit_id'];

    /// 上一次Unity打包Commit id
    String? unityCommitId = config?['unityCommitId'];

    /// 上一次编译Unity的Build Version Id
    int? unityBuildVersionId = config?['build_number'];

    /// 将Flutter工程切换分支到代码最新
    await pullAndSwitchBranch(flutterProjectDir.path, environment.branch);

    /// 获取当前Flutter工程的Commit id
    final flutterCurrentCommitId =
        await getCurrentCommitHash(flutterProjectDir.path);

    /// 将Unity工程切换分支到代码最新
    await pullAndSwitchBranch(unityProjectDir.path, environment.branch);

    /// 获取当前Unity工程的Commit id
    final unityCurrentCommitId =
        await getCurrentCommitHash(unityProjectDir.path);

    final buildVersionId = await getUnityBuildVersion(unityProjectDir.path);

    if (flutterCommitId == flutterCurrentCommitId &&
        unityBuildVersionId == buildVersionId &&
        !environment.forceBuild) {
      loggerWarning('检测当前打包版本和上次打包版本一致，不需要进行打包！如果强制打包请设置FORCE_BUILD=true');
      return;
    }

    /// 复制Unity静态库到指定位置
    final buildUnityCommitId = await copyUnityStaticLibrary(
      buildVersionId: buildVersionId,
      commitHash: unityCurrentCommitId,
      branch: environment.branch,
    );

    /// 复制Flutter静态库到指定位置
    final buildFlutterCommitId = await copyFlutterStaticLibrary(
      commitHash: flutterCurrentCommitId,
      branch: environment.branch,
    );

    /// 更新打包配置
  }

  /// 复制Unity静态库到指定位置
  Future<String> copyUnityStaticLibrary({
    required int buildVersionId,
    required String commitHash,
    required String branch,
  }) async {
    /// 根据VersionId 查询本地是否有已经存在的Unity静态库
    final cacheCommitHash = await unityCache.getLatestCommitHash(
      branch: environment.branch,
      buildVersionId: buildVersionId,
    );

    if (cacheCommitHash != null &&
        await unityFrameworkAarCache.isCommitHashCacheExists(cacheCommitHash)) {
      loggerDebug('本地存在缓存Unity静态库，直接进行复制');
      final zipPath =
          unityFrameworkAarCache.getCommitHashCachePath(cacheCommitHash);
      await copyZipToDir(zipPath, unityFrameworkAarDir);
      return cacheCommitHash;
    } else {
      await buildUnityStaticLibrary();
      final zipPath = unityFrameworkAarCache.getCommitHashCachePath(commitHash);
      await copyZipToDir(zipPath, unityFrameworkAarDir);
      return commitHash;
    }
  }

  /// 执行打包 Unity 静态库命令
  Future<void> buildUnityStaticLibrary();

  Future<String> copyFlutterStaticLibrary({
    required String commitHash,
    required String branch,
  }) async {
    if (!await flutterFrameworkAarCache.isCommitHashCacheExists(commitHash)) {
      await buildFlutterStaticLibrary();
    }
    final zipPath = flutterFrameworkAarCache.getCommitHashCachePath(commitHash);
    await copyZipToDir(zipPath, flutterFrameworkAarDir);
    return commitHash;
  }

  /// 执行打包 Flutter 静态库命令
  Future<void> buildFlutterStaticLibrary();
}
