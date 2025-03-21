import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:meta_tool/app_home_dir.dart';
import 'package:meta_tool/appwrite_server.dart';
import 'package:meta_tool/commands/upload/upload_app_environment.dart';
import 'package:meta_tool/common.dart';
import 'package:meta_tool/get_git_log.dart';
import 'package:meta_tool/upload_sentry.dart';
import 'package:process_runner/process_runner.dart';
import 'package:prompts/prompts.dart' as prompts;

abstract class UploadAppCommand extends Command {
  late UploadAppEnvironment environment;
  String get buildType;

  String get platform;

  late AppwriteServer appwriteServer;
  late AppHomeDir appHomeDir;
  late ProcessRunner buildAppRunner;

  UploadAppCommand() {
    argParser.addOption(
      'workspace',
      help: 'App工作目录',
      defaultsTo: Directory.current.path,
    );
    argParser.addFlag('isUseEnvironment', help: '是否使用环境变量', defaultsTo: false);
  }

  @override
  FutureOr? run() async {
    appHomeDir = AppHomeDir(workspace: environment.workspace);
    buildAppRunner =
        await createBuildAppRunner(appHomeDir, environment.isStore);
    bool isUseEnvironment = argResults?['isUseEnvironment'];
    environment = isUseEnvironment
        ? UploadAppEnvironment.fromEnvironment(Platform.environment)
        : await chooseEnvironment();

    appwriteServer = AppwriteServer(
      endpoint: environment.appwriteBuildEnvironment.endpoint,
      projectId: environment.appwriteBuildEnvironment.projectId,
      apiKey: environment.appwriteBuildEnvironment.apiKey,
    );

    /// 查询最新的打包版本配置
    final config = await appwriteServer.getCurrentBranchBuildConfig(
      databaseId: environment.appwriteBuildEnvironment.databaseId,
      collectionId: environment.appwriteBuildEnvironment.collectionId,
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
    await pullAndSwitchBranch(
      appHomeDir.flutterDir.path,
      environment.branch,
    );

    /// 获取当前Flutter工程的Commit id
    final flutterCurrentCommitId =
        await getCurrentCommitHash(appHomeDir.flutterDir.path);

    /// 将Unity工程切换分支到代码最新
    await pullAndSwitchBranch(
      environment.unityProjectDir,
      environment.unityBranchName,
    );

    /// 获取当前Unity工程的Commit id
    final unityCurrentCommitId =
        await getCurrentCommitHash(environment.unityProjectDir);

    final buildVersionId =
        await getUnityBuildVersion(environment.unityProjectDir);

    loggerDebug('正在获取当前Flutter变更日志');
    final flutterChangeLog = await GetGitLog(
      root: appHomeDir.flutterDir.path,
      beforeCommitId: flutterCommitId,
    ).get();

    loggerDebug('正在获取当前Unity变更日志');
    final unityChangeLog = await GetGitLog(
      root: environment.unityProjectDir,
      beforeCommitId: unityCommitId,
    ).get();

    final formatChangeLog = formatGitLog(
      '''
Flutter更新日志:$flutterCurrentCommitId
$flutterChangeLog
''',
      '''
Unity更新日志:$unityCurrentCommitId
$unityChangeLog
''',
    );
    final changeLog = '''
[Flutter]: ${environment.branch}
[Unity]: ${environment.unityBranchName}
[IOS]: ${environment.iosBranch}
[Android]: ${environment.androidBranch}
[Tag]: ${environment.tag}
[version]: ${environment.buildName}(${environment.buildNumber})
-----------------------
$formatChangeLog
-----------------------
''';
    loggerWarning('''
当前的打包更新日志为:
$changeLog
''');

    if (flutterCommitId == flutterCurrentCommitId &&
        unityBuildVersionId == buildVersionId &&
        !environment.forceBuild) {
      loggerSuccess('检测当前打包版本和上次打包版本一致，不需要进行打包！如果强制打包请设置FORCE_BUILD=true');
      return;
    }

    loggerDebug('开始复制Unity静态库到指定位置');
    await copyUnityStaticLibrary(buildVersionId);

    loggerDebug('开始复制Flutter静态库到指定位置');
    await copyFlutterStaticLibrary(flutterCurrentCommitId);

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
      databaseId: environment.appwriteBuildEnvironment.databaseId,
      collectionId: environment.appwriteBuildEnvironment.collectionId,
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
      flutterProjectPath: appHomeDir.flutterDir.path,
      project: environment.sentryProject,
      url: environment.sentryUrl,
      authToken: environment.sentryAuthToken,
      org: environment.sentryOrg,
      dist: environment.sentryDist,
      release: environment.buildName,
    ).run();
  }

  /// 复制Unity静态库到指定位置
  Future<String?> copyUnityStaticLibrary(int buildVersionId) async {
    final appRunner = await createAppRunner(appHomeDir);
    await appRunner.runProcess(
      [
        'metax',
        'cache',
        'use',
        '--buildPlatform',
        environment.platform,
        '--buildConfiguration',
        'release',
        '--buildLibrary',
        'unity',
        '--buildType',
        buildType,
        '--branch',
        environment.branch,
        '--isStore',
        environment.isStore.toString(),
        '--buildId',
        buildVersionId.toString(),
      ],
    );
    return null;
  }

  Future<String?> copyFlutterStaticLibrary(String commitHash) async {
    await ProcessRunner().runProcess(
      [
        'metax',
        'cache',
        'use',
        '--buildPlatform',
        environment.platform,
        '--buildConfiguration',
        'release',
        '--buildLibrary',
        'flutter',
        '--buildType',
        buildType,
        '--branch',
        environment.branch,
        '--isStore',
        environment.isStore.toString(),
        '--commitHash',
        commitHash,
      ],
    );
    return null;
  }

  /// 进行打包
  Future<void> buildApp();

  /// 上传ipa/apk
  Future<void> uploadApp({required String log});

  /// 复制ipa/apk到指定位置
  Future<void> copyIpaOrApkToBuildDir();

  /// 发送日志
  Future<void> sendLog({required String log});

  /// 通过交互获取环境变量
  Future<UploadAppEnvironment> chooseEnvironment() async {
    final buildName = prompts.get('请输入版本号(比如1.0.0):');
    final flutterBranch = prompts.choose(
      '请选择Flutter分支(比如main):',
      await getLatestBranchList(appHomeDir.flutterDir.path),
    );
    final unityBranch = prompts.choose(
      '请选择Unity分支(比如main):',
      await getLatestBranchList(environment.unityProjectDir),
    );
    String? iosBranch;
    String? androidBranch;
    if (environment.platform == 'ios') {
      iosBranch = prompts.choose(
        '请选择IOS分支(比如main):',
        await getLatestBranchList(appHomeDir.iosDir.path),
      );
    } else {
      androidBranch = prompts.choose(
        '请选择Android分支(比如main):',
        await getLatestBranchList(appHomeDir.androidDir.path),
      );
    }
    final forceBuild = prompts.choose('是否强制打包?', [
      '是',
      '否',
    ]);
    final upload = prompts.choose('是否上传?', [
      '是',
      '否',
    ]);
    final sendLog = prompts.choose('是否发送日志?', [
      '是',
      '否',
    ]);
    final isStore = prompts.choose('是否是市场包?', [
      '是',
      '否',
    ]);

    Map<String, String> environmentMap = await loadBuildAppEnvironment(
      appHomeDir,
      isStore == '是',
    );

    if (platform == 'android') {
      String zealotChannelKey = environmentMap['TEST_ZEALOT_CHANNEL_KEY']!;
      if (isStore == '是') {
        final zealotChannel = prompts.choose(
          '请选择Zealot渠道',
          [
            'Winner',
            'Tencent',
            'HuaWei',
            'XiaoMi',
            'Oppo',
            'MeiZu',
            'Vivo',
            'Honor',
            'Samsung',
          ],
        );
        final keys = {
          'Winner': environmentMap['WINNER_ZEALOT_CHANNEL_KEY']!,
          'Tencent': environmentMap['TENCENT_ZEALOT_CHANNEL_KEY']!,
          'HuaWei': environmentMap['HUAWEI_ZEALOT_CHANNEL_KEY']!,
          'XiaoMi': environmentMap['XIAOMI_ZEALOT_CHANNEL_KEY']!,
          'Oppo': environmentMap['OPPO_ZEALOT_CHANNEL_KEY']!,
          'MeiZu': environmentMap['MEIZU_ZEALOT_CHANNEL_KEY']!,
          'Vivo': environmentMap['VIVO_ZEALOT_CHANNEL_KEY']!,
          'Honor': environmentMap['HONOR_ZEALOT_CHANNEL_KEY']!,
          'Samsung': environmentMap['SAMSUNG_ZEALOT_CHANNEL_KEY']!,
        };
        zealotChannelKey = keys[zealotChannel]!;
      }
    }

    return UploadAppEnvironment.choose(
      platform: platform,
      workspace: appHomeDir.workspace,
      buildName: buildName,
      branch: flutterBranch!,
      forceBuild: forceBuild == '是',
      unityBranchName: unityBranch!,
      upload: upload == '是',
      sendLog: sendLog == '是',
      isStore: isStore == '是',
      iosBranch: iosBranch!,
      androidBranch: androidBranch!,
      environment: environmentMap,
    );
  }
}
