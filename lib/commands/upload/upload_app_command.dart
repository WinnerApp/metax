import 'dart:async';

import 'package:args/command_runner.dart';
import 'package:darty_json_safe/darty_json_safe.dart';
import 'package:meta_tool/appwrite_server.dart';
import 'package:meta_tool/argument_get.dart';
import 'package:meta_tool/common.dart';
import 'package:meta_tool/define.dart';
import 'package:meta_tool/get_git_log.dart';
import 'package:meta_tool/unity_environment.dart';
import 'package:meta_tool/upload_app_environment.dart';
import 'package:meta_tool/upload_sentry.dart';
import 'package:process_runner/process_runner.dart';

abstract class UploadAppCommand extends Command {
  String get buildType;

  String get platform;

  late AppwriteServer appwriteServer;
  late ProcessRunner buildAppRunner;

  UploadAppCommand() {
    argParser.addOption(
      'flutterBranch',
      help: 'Flutter分支',
    );
    argParser.addOption(
      'unityBranch',
      help: 'Unity分支',
    );
    argParser.addOption(
      'buildName',
      help: '打包版本号',
    );
    argParser.addOption(
      'iosBranch',
      help: 'IOS分支',
    );
    argParser.addOption(
      'androidBranch',
      help: 'Android分支',
    );
    argParser.addOption(
      'forceBuild',
      help: '是否强制打包',
      allowed: ['true', 'false'],
    );
    argParser.addOption(
      'upload',
      help: '是否上传',
      allowed: ['true', 'false'],
    );
    argParser.addOption(
      'sendLog',
      help: '是否发送日志',
      allowed: ['true', 'false'],
    );
    argParser.addOption(
      'isStore',
      help: '是否是市场包',
      allowed: ['true', 'false'],
    );
    argParser.addOption(
      'zealotChannel',
      help: 'Zealot渠道',
      allowed: [
        'Winner',
        'Tencent',
        'HuaWei',
        'XiaoMi',
        'Oppo',
        'MeiZu',
        'Vivo',
        'Honor',
        'Samsung'
      ],
    );
    argParser.addOption(
      'initFlutterEnvironment',
      help: '是否初始化Flutter环境',
      allowed: ['true', 'false'],
      defaultsTo: 'true',
    );
  }

  @override
  FutureOr? run() async {
    final unityEnvironment = UnityEnvironment.fromEnvironment(appHomeDir);
    final environment = await chooseEnvironment(unityEnvironment);

    buildAppRunner =
        await createBuildAppRunner(appHomeDir, environment.isStore);

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
    int? unityBuildVersionId = JSON(config)['build_number'].int;

    /// 将Flutter工程切换分支到代码最新
    await switchBranch(
      appHomeDir.flutterDir.path,
      environment.branch,
    );

    /// 获取当前Flutter工程的Commit id
    final flutterCurrentCommitId =
        await getCurrentCommitHash(appHomeDir.flutterDir.path);
    late String unityProjectWorkspace;
    if (platform == 'ios') {
      unityProjectWorkspace = unityEnvironment.iosUnityWorkspace;
    } else {
      unityProjectWorkspace = unityEnvironment.androidUnityWorkspace;
    }

    /// 将Unity工程切换分支到代码最新
    await switchBranch(
      unityProjectWorkspace,
      environment.unityBranchName,
    );

    /// 获取当前Unity工程的Commit id
    final unityCurrentCommitId =
        await getCurrentCommitHash(unityProjectWorkspace);

    final buildVersionId = await getUnityBuildVersion(unityProjectWorkspace);

    if (platform == 'ios') {
      await switchBranch(appHomeDir.iosDir.path, environment.iosBranch);
    } else {
      await switchBranch(appHomeDir.androidDir.path, environment.androidBranch);
    }

    loggerDebug('正在获取当前Flutter变更日志');
    final flutterChangeLog = await GetGitLog(
      root: appHomeDir.flutterDir.path,
      beforeCommitId: flutterCommitId,
    ).get();

    loggerDebug('正在获取当前Unity变更日志');
    final unityChangeLog = await GetGitLog(
      root: unityProjectWorkspace,
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
    await copyUnityStaticLibrary(buildVersionId, environment);

    loggerDebug('开始复制Flutter静态库到指定位置');
    await copyFlutterStaticLibrary(flutterCurrentCommitId, environment);

    final isInitFlutterEnvironment =
        argResults?['initFlutterEnvironment'] == 'true';
    if (isInitFlutterEnvironment) {
      /// 开始初始化Flutter环境
      await initFlutterEnvironment(
        appHomeDir: appHomeDir,
        buildType: buildType,
        configuration: 'release',
        isStore: environment.isStore,
      );
    }

    await setVersionNumber(
      buildName: environment.buildName,
      buildNumber: environment.buildNumber,
      platform: environment.platform,
    );

    loggerDebug('开始进行打包......');
    await buildApp();

    loggerDebug('开始复制ipa/apk到指定位置');
    await copyIpaOrApkToBuildDir(environment);

    if (environment.upload) {
      loggerDebug('开始上传ipa/apk......');
      final uploadLog =
          '[Tag:${environment.tag}][Flutter(${environment.branch})][Unity(${environment.unityBranchName})]  新版本发布了，请下载体验!';
      await uploadApp(log: uploadLog, environment: environment);
    }

    if (environment.sendLog) {
      loggerDebug('开始发送日志......');
      await sendLog(log: changeLog, environment: environment).catchError((e) {
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
  Future<void> copyUnityStaticLibrary(
      int buildVersionId, UploadAppEnvironment environment) async {
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
        '--buildId',
        buildVersionId.toString(),
        '--unityBranch',
        environment.unityBranchName,
        getUseMockCommand(),
      ],
      printOutput: true,
    );
  }

  Future<void> copyFlutterStaticLibrary(
    String commitHash,
    UploadAppEnvironment environment,
  ) async {
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
        '--commitHash',
        commitHash,
        getUseMockCommand(),
      ],
      printOutput: true,
    );
  }

  /// 进行打包
  Future<void> buildApp();

  /// 上传ipa/apk
  Future<void> uploadApp({
    required String log,
    required UploadAppEnvironment environment,
  });

  /// 复制ipa/apk到指定位置
  Future<void> copyIpaOrApkToBuildDir(UploadAppEnvironment environment);

  /// 发送日志
  Future<void> sendLog({
    required String log,
    required UploadAppEnvironment environment,
  });

  /// 通过交互获取环境变量
  Future<UploadAppEnvironment> chooseEnvironment(
      UnityEnvironment unityEnvironment) async {
    final buildName = ArgumentGet(argResults).getString('buildName', '请输入版本号');
    final flutterBranch = ArgumentGet(argResults).getString(
      'flutterBranch',
      '请输入Flutter分支',
      allowed: await getLatestBranchList(appHomeDir.flutterDir.path),
    );
    final unityBranch = ArgumentGet(argResults).getString(
      'unityBranch',
      '请选择Unity分支',
      allowed: await getLatestBranchList(
        unityEnvironment.getPlatfromUnityWorkspace(platform),
      ),
    );
    String? iosBranch;
    String? androidBranch;
    if (platform == 'ios') {
      iosBranch = ArgumentGet(argResults).getString(
        'iosBranch',
        '请选择IOS分支',
        allowed: await getLatestBranchList(appHomeDir.iosDir.path),
      );
    } else {
      androidBranch = ArgumentGet(argResults).getString(
        'androidBranch',
        '请选择Android分支',
        allowed: await getLatestBranchList(appHomeDir.androidDir.path),
      );
    }
    final forceBuild = ArgumentGet(argResults).getString(
      'forceBuild',
      '是否强制打包?',
      allowed: ['true', 'false'],
    );
    final upload = ArgumentGet(argResults).getString(
      'upload',
      '是否上传?',
      allowed: ['true', 'false'],
    );
    final sendLog = ArgumentGet(argResults).getString(
      'sendLog',
      '是否发送日志?',
      allowed: ['true', 'false'],
    );
    final isStore = ArgumentGet(argResults).getString(
      'isStore',
      '是否是市场包?',
      allowed: ['true', 'false'],
    );

    Map<String, String> environmentMap = loadBuildAppEnvironment(
      appHomeDir,
      isStore == 'true',
    );

    loggerDebug('环境变量:${environmentMap.toString()}');
    String zealotChannelKey = readBuildAppEnv('ZEALOT_CHANNEL_KEY', appHomeDir);
    if (platform == 'android') {
      if (isStore == '是') {
        final zealotChannel = ArgumentGet(argResults).getString(
          'zealotChannel',
          '请选择Zealot渠道',
          allowed: [
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
      environmentMap['ZEALOT_CHANNEL_KEY'] = zealotChannelKey;
    }

    return UploadAppEnvironment.choose(
      platform: platform,
      workspace: appHomeDir.workspace,
      buildName: buildName,
      branch: flutterBranch,
      forceBuild: forceBuild == 'true',
      unityBranchName: unityBranch,
      upload: upload == 'true',
      sendLog: sendLog == 'true',
      isStore: isStore == 'true',
      iosBranch: iosBranch ?? '',
      androidBranch: androidBranch ?? '',
      appHomeDir: appHomeDir,
      unityEnvironment: unityEnvironment,
      zealotChannelKey: zealotChannelKey,
    );
  }
}
