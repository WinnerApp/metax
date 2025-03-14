import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:meta_tool/app_home_dir.dart';
import 'package:meta_tool/appwrite_server.dart';
import 'package:meta_tool/commands/upload/upload_app_environment.dart';
import 'package:meta_tool/common.dart';
import 'package:meta_tool/define.dart';
import 'package:meta_tool/get_git_log.dart';
import 'package:meta_tool/upload_sentry.dart';

abstract class UploadAppCommand extends Command {
  late UploadAppEnvironment environment;

  Directory get unityProjectDir;
  Directory get unityFrameworkAarDir;
  Directory get flutterFrameworkAarDir;
  Directory get flutterProjectDir => appHomeDir.flutterDir;
  Directory get iosProjectDir => appHomeDir.iosDir;
  Directory get androidProjectDir => appHomeDir.androidDir;

  BuildPublish get buildPublish =>
      environment.isStore ? BuildPublish.store : BuildPublish.test;

  String get platform;

  late AppwriteServer appwriteServer;
  late AppHomeDir appHomeDir;

  @override
  FutureOr? run() async {
    environment = UploadAppEnvironment(platform: platform);

    appwriteServer = AppwriteServer(
      endpoint: environment.appwriteEndpoint,
      projectId: environment.appwriteProjectId,
      apiKey: environment.appwriteApiKey,
    );

    appHomeDir = AppHomeDir(workspace: environment.workspace);

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

    loggerDebug('开始复制Unity静态库到指定位置');
    // final buildUnityCommitId = await copyUnityStaticLibrary(
    //   buildVersionId: buildVersionId,
    //   commitHash: unityCurrentCommitId,
    //   branch: environment.branch,
    // );

    loggerDebug('开始复制Flutter静态库到指定位置');
    // final buildFlutterCommitId = await copyFlutterStaticLibrary(
    //   commitHash: flutterCurrentCommitId,
    //   branch: environment.branch,
    // );

    loggerDebug('正在获取当前Flutter变更日志');
    final flutterChangeLog = await GetGitLog(
      root: flutterProjectDir.path,
      beforeCommitId: flutterCommitId,
    ).get();

    loggerDebug('正在获取当前Unity变更日志');
    final unityChangeLog = await GetGitLog(
      root: unityProjectDir.path,
      beforeCommitId: unityCommitId,
    ).get();

    final changeLog = formatGitLog(
      '''
[Flutter]: ${environment.branch}
[Unity]: ${environment.unityBranchName}
[Tag]: ${environment.tag}
[version]: ${environment.buildName}(${environment.buildNumber})
-----------------------
Flutter更新日志:$flutterCurrentCommitId
$flutterChangeLog
''',
      '''
Unity更新日志:$unityCurrentCommitId
$unityChangeLog
-----------------------
''',
    );
    loggerWarning('''
当前的打包更新日志为:
$changeLog
''');

    loggerDebug('开始进行打包......');
    await buildApp();

    loggerDebug('开始复制ipa/apk到指定位置');
    await copyIpaOrApkToBuildDir();

    if (environment.upload) {
      loggerDebug('开始上传ipa/apk......');
      final uploadLog =
          '[Tag:${environment.tag}][Flutter(${environment.branch})][Unity(${environment.unityBranchName})]  新版本发布了，请下载体验!';
      await uploadApp(log: uploadLog);
    }

    if (environment.sendLog) {
      loggerDebug('开始发送日志......');
      await sendLog(log: changeLog).catchError((e) {
        loggerError('发送日志失败:${e.toString()}');
      });
    }

    /// 更新配置
    await appwriteServer.updateBuildConfig(
      databaseId: environment.appwriteDatabaseId,
      collectionId: environment.appwriteCollectionId,
      platform: environment.platform,
      branch: environment.branch,
      unityBranch: environment.unityBranchName,
      buildName: environment.buildName,
      flutterCommitId: flutterCurrentCommitId,
      unityCommitId: unityCurrentCommitId,
      buildNumber: buildVersionId,
    );

    /// 上传sentry符号
    await UploadSentrySymbols(
      flutterProjectPath: flutterProjectDir.path,
      project: environment.sentryProject,
      url: environment.sentryUrl,
      authToken: environment.sentryAuthToken,
      org: environment.sentryOrg,
      dist: environment.sentryDist,
      release: environment.buildName,
    ).run();
  }

  /// 复制Unity静态库到指定位置
  Future<String> copyUnityStaticLibrary({
    required int buildVersionId,
    required String commitHash,
    required String branch,
  }) async {
    /// 根据VersionId 查询本地是否有已经存在的Unity静态库
    // final cacheCommitHash = await unityCache.getLatestCommitHash(
    //   branch: environment.branch,
    //   buildVersionId: buildVersionId,
    // );

    // if (cacheCommitHash != null &&
    //     await unityFrameworkAarCache.isCommitHashCacheExists(cacheCommitHash)) {
    //   loggerDebug('本地存在缓存Unity静态库，直接进行复制');
    //   final zipPath =
    //       unityFrameworkAarCache.getCommitHashCachePath(cacheCommitHash);
    //   await copyZipToDir(zipPath, unityFrameworkAarDir);
    //   return cacheCommitHash;
    // } else {
    //   await buildUnityStaticLibrary();
    //   final zipPath = unityFrameworkAarCache.getCommitHashCachePath(commitHash);
    //   await copyZipToDir(zipPath, unityFrameworkAarDir);
    //   return commitHash;
    // }
    throw UnimplementedError();
  }

  /// 执行打包 Unity 静态库命令
  Future<void> buildUnityStaticLibrary();

  Future<String> copyFlutterStaticLibrary({
    required String commitHash,
    required String branch,
  }) async {
    // if (!await flutterFrameworkAarCache.isCommitHashCacheExists(commitHash)) {
    //   await buildFlutterStaticLibrary();
    // }
    // final zipPath = flutterFrameworkAarCache.getCommitHashCachePath(commitHash);
    // await copyZipToDir(zipPath, flutterFrameworkAarDir);
    return commitHash;
  }

  /// 执行打包 Flutter 静态库命令
  Future<void> buildFlutterStaticLibrary();

  /// 进行打包
  Future<void> buildApp();

  /// 上传ipa/apk
  Future<void> uploadApp({required String log});

  /// 复制ipa/apk到指定位置
  Future<void> copyIpaOrApkToBuildDir();

  /// 发送日志
  Future<void> sendLog({required String log});
}
