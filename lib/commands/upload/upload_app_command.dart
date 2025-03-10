import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:meta_tool/appwrite_server.dart';
import 'package:meta_tool/cache/framework_aar_cache.dart';
import 'package:meta_tool/cache/unity_cache.dart';
import 'package:meta_tool/common.dart';
import 'package:meta_tool/define.dart';
import 'package:path/path.dart';
import 'package:process_runner/process_runner.dart';

class UploadAppCommand extends Command {
  @override
  String get name => 'app';

  @override
  String get description => '上传安装包';

  @override
  FutureOr? run() async {
    loggerDebug('正在检测打包环境...');
    final workspace = readEnv('WORKSPACE');
    final platform = readEnv('PLATFROM');
    final buildName = readEnv('BUILD_NAME');
    final branch = readEnv('BRANCH');
    final forceBuild = readEnv('FORCE_BUILD') == 'true';
    final unityBranchName = readEnv('UNITY_BRANCH_NAME');
    final upload = readEnv('UPLOAD') == 'true';
    final sendLog = readEnv('SEND_LOG') == 'true';
    final isStore = readEnv('IS_STORE') == 'true';

    loggerDebug('正在检测Unity环境变量...');
    final unityWorkspace = readEnv('UNITY_WORKSPACE');
    final iosUnityPath = readEnv('IOS_UNITY_PATH');
    final androidUnityPath = readEnv('ANDROID_UNITY_PATH');
    checkEnv('UNITY_ENGINE_PATH');

    loggerDebug('正在检测日志hook配置...');
    final iosHookUrl = checkEnv('IOS_HOOK_URL');
    final androidHookUrl = checkEnv('ANDROID_HOOK_URL');

    loggerDebug('正在检测iOS打包配置...');
    checkEnv('APP_STORE_CONNECT_API_KEY_FILEPATH');
    checkEnv('APP_STORE_CONNECT_API_KEY_ID');
    checkEnv('APP_STORE_CONNECT_API_ISSUER_ID');
    checkEnv('APP_IDENTIFIER');
    checkEnv('APP_ID');

    loggerDebug('正在检测Appwrite配置...');
    final appwriteEndpoint = readEnv('APPWRITE_ENDPOINT');
    final appwriteProjectId = readEnv('APPWRITE_PROJECT_ID');
    final appwriteApiKey = readEnv('APPWRITE_API_KEY');
    final appwriteDatabaseId = readEnv('APPWRITE_DATABASE_ID');
    final appwriteCollectionId = readEnv('APPWRITE_COLLECTION_ID');

    loggerDebug('正在检测Sentry配置...');
    checkEnv('SENTRY_URL');
    checkEnv('SENTRY_AUTH_TOKEN');
    checkEnv('SENTRY_ORG');
    checkEnv('SENTRY_PROJECT');

    loggerDebug('正在检测Zealot配置...');
    checkEnv('ZEALOT_ENDPOINT');
    checkEnv('ZEALOT_TOKEN');
    checkEnv('ZEALOT_CHANNEL_KEY');

    loggerDebug('正在检测Umeng配置...');
    checkEnv('UMENG_APPKEY');
    checkEnv('UMENG_MESSAGE_SECRET');
    checkEnv('UMENG_CHANNEL');

    late String tag;
    if (readEnv('TAG').isNotEmpty) {
      tag = readEnv('TAG');
    } else {
      tag = isStore ? "[市场包]" : "[测试包]";
    }

    final flutterDir = Directory(join(workspace, 'metaapp_flutter'));
    final iosDir = Directory(join(workspace, 'ios'));
    final androidDir = Directory(join(workspace, 'android'));

    if (!flutterDir.existsSync() &&
        !iosDir.existsSync() &&
        !androidDir.existsSync()) {
      loggerError('打包目录不正确！打包目录需要包含ios、android、metaapp_flutter目录');
      return;
    }

    /// 查询最新的打包版本配置
    final config = await AppwriteServer(
      endpoint: appwriteEndpoint,
      projectId: appwriteProjectId,
      apiKey: appwriteApiKey,
    ).getCurrentBranchBuildConfig(
      databaseId: appwriteDatabaseId,
      collectionId: appwriteCollectionId,
      platform: platform,
      branch: branch,
      unityBranch: unityBranchName,
      buildName: buildName,
    );

    /// 上一次Flutter打包Commit id
    String? flutterCommitId = config?['flutter_commit_id'];

    /// 上一次Unity打包Commit id
    String? unityCommitId = config?['unityCommitId'];

    /// 上一次编译Unity的Build Version Id
    int? unityBuildVersionId = config?['build_number'];

    /// 将Flutter工程切换分支到代码最新
    await pullAndSwitchBranch(flutterDir.path, branch);

    /// 获取当前Flutter工程的Commit id
    final flutterCurrentCommitId = await getCurrentCommitHash(flutterDir.path);

    late String unityDir;
    if (platform == 'ios') {
      unityDir = Directory(join(unityWorkspace, iosUnityPath)).path;
    } else {
      unityDir = Directory(join(unityWorkspace, androidUnityPath)).path;
    }

    /// 将Unity工程切换分支到代码最新
    await pullAndSwitchBranch(unityDir, branch);

    /// 获取当前Unity工程的Commit id
    final unityCurrentCommitId = await getCurrentCommitHash(unityDir);

    final buildVersionId = await getUnityBuildVersion(unityDir);

    if (flutterCommitId == flutterCurrentCommitId &&
        unityBuildVersionId == buildVersionId &&
        !forceBuild) {
      loggerWarning('检测当前打包版本和上次打包版本一致，不需要进行打包！如果强制打包请设置FORCE_BUILD=true');
      return;
    }

    /// 查询本地是否有打包的Unity Framework AAR文件
    final frameworkAarCache = FrameworkAarCache(
      platform: platform == 'ios' ? BuildPlatform.ios : BuildPlatform.android,
      configuration: BuildConfiguration.release,
      type: platform == 'ios' ? BuildType.framework : BuildType.aar,
      library: BuildLibrary.unity,
    );

    final lastCommitId = await frameworkAarCache.getLatestCommitIdFromBranch(
      branch,
      buildVersionId,
    );

    bool needUpdateUnity = true;
    if (lastCommitId != null &&
        await frameworkAarCache.isCommitHashCacheExists(lastCommitId)) {}
  }

  /// 复制Unity静态库到指定位置
  Future<void> copyUnityStaticLibrary({
    required int buildVersionId,
    required String branch,
    required String platform,
  }) async {
    /// 根据VersionId 查询本地是否有已经存在的Unity静态库
    final cache = UnityCache(platform: platform == 'ios' ? BuildPlatform.ios : BuildPlatform.android,);
    final cacheCommitHash = await cache.getLatestCommitHash(
      branch: branch,
      buildVersionId: buildVersionId,
    );

    if (cacheCommitHash == null || !await cache.isCommitHashCacheExists(cacheCommitHash)) {
        if (platform == 'ios') {
          await ProcessRunner().runProcess([]);
        } else {platform}
    }


    
  }
}
