import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dart_appwrite/models.dart';
import 'package:meta_tool/appwrite_server.dart';
import 'package:meta_tool/argument_get.dart';
import 'package:meta_tool/common.dart';
import 'package:meta_tool/define.dart';
import 'package:meta_tool/get_git_log.dart';
import 'package:meta_tool/git_submodule_parse.dart';
import 'package:meta_tool/unity_environment.dart';
import 'package:meta_tool/upload_app_environment.dart';
import 'package:meta_tool/upload_sentry.dart';
import 'package:path/path.dart';
import 'package:process_runner/process_runner.dart';

abstract class UploadAppCommand extends Command {
  String get buildType;

  String get platform;

  late AppwriteServer appwriteServer;
  late ProcessRunner buildAppRunner;

  UploadAppCommand() {
    argParser.addOption(
      'branch',
      help: 'melos分支',
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
        'Huawei',
        'Xiaomi',
        'Oppo',
        'Meizu',
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
    argParser.addOption(
      'copyIpaOrApkToBuildDir',
      help: '复制ipa/apk到指定位置',
    );
  }

  @override
  FutureOr? run() async {
    String? copyDir = argResults?['copyIpaOrApkToBuildDir'];

    final unityEnvironment = UnityEnvironment.fromEnvironment(appHomeDir);
    UploadAppEnvironment environment =
        await chooseEnvironment(unityEnvironment);

    loggerDebug('platform:${environment.platform}');
    loggerDebug('workspace:${environment.workspace}');
    loggerDebug('buildName:${environment.buildName}');
    loggerDebug('forceBuild:${environment.forceBuild}');
    loggerDebug('melosBranch:${environment.melosBranch}');
    loggerDebug('unityBranchName:${environment.unityBranchName}');
    loggerDebug('upload:${environment.upload}');
    loggerDebug('sendLog:${environment.sendLog}');
    loggerDebug('isStore:${environment.isStore}');
    loggerDebug('buildNumber:${environment.buildNumber}');
    loggerDebug('unityWorkspace:${unityEnvironment.unityWorkspace}');
    loggerDebug('iosUnityPath:${unityEnvironment.iosUnityPath}');
    loggerDebug('androidUnityPath:${unityEnvironment.androidUnityPath}');
    loggerDebug('unityEnginePath:${unityEnvironment.unityEnginePath}');
    loggerDebug('iosHookUrl:${environment.iosHookUrl}');
    loggerDebug('androidHookUrl:${environment.androidHookUrl}');
    loggerDebug(
        'appStoreConnectApiKeyFilepath:${environment.appStoreConnectApiKeyFilepath}');
    loggerDebug(
        'appStoreConnectApiKeyId:${environment.appStoreConnectApiKeyId}');
    loggerDebug(
        'appStoreConnectApiIssuerId:${environment.appStoreConnectApiIssuerId}');
    loggerDebug('appIdentifier:${environment.appIdentifier}');
    loggerDebug('appId:${environment.appId}');
    loggerDebug(
        'databaseId:${environment.appwriteBuildEnvironment.databaseId}');
    loggerDebug(
        'collectionId:${environment.appwriteBuildEnvironment.buildConfigCollectionId}');
    loggerDebug('endpoint:${environment.appwriteBuildEnvironment.endpoint}');
    loggerDebug('projectId:${environment.appwriteBuildEnvironment.projectId}');
    loggerDebug('apiKey:${environment.appwriteBuildEnvironment.apiKey}');
    loggerDebug('zealotEndpoint:${environment.zealotEndpoint}');
    loggerDebug('zealotToken:${environment.zealotToken}');
    loggerDebug('zealotChannelKey:${environment.zealotChannelKey}');
    loggerDebug('umengAppKey:${environment.umengAppKey}');
    loggerDebug('umengMessageSecret:${environment.umengMessageSecret}');
    loggerDebug('umengChannel:${environment.umengChannel}');
    loggerDebug('sentryProject:${environment.sentryProject}');
    loggerDebug('sentryUrl:${environment.sentryUrl}');
    loggerDebug('sentryAuthToken:${environment.sentryAuthToken}');
    loggerDebug('sentryOrg:${environment.sentryOrg}');
    loggerDebug('sentryDist:${environment.sentryDist}');
    loggerDebug('tag:${environment.tag}');

    /// Flutter是否需要打包
    bool isFlutterBuild = false;

    /// Unity是否需要打包
    bool isUnityBuild = false;
    List<AppwriteBuildBranchConfig> buildBranchConfigs = [];

    buildAppRunner = await createBuildAppRunner(
      appHomeDir,
      environment.isStore,
    );

    appwriteServer = AppwriteServer(
      endpoint: environment.appwriteBuildEnvironment.endpoint,
      projectId: environment.appwriteBuildEnvironment.projectId,
      apiKey: environment.appwriteBuildEnvironment.apiKey,
    );

    await switchBranch(appHomeDir.workspace, environment.melosBranch);

    /// 将当前项目进行初始化
    /// 1. 更新最新的Git submodule
    await buildAppRunner.runProcess(
      [
        'bash',
        "init_git_submodule.sh",
      ],
      workingDirectory: Directory(environment.workspace),
      printOutput: true,
    );

    /// 2 分析出当前项目的submodule
    final gitSubmodulePath = join(environment.workspace, '.gitmodules');
    final gitSubmodules = await parseGitmodulesFile(gitSubmodulePath);

    /// 得到最新melos工程的分支
    final melosBranch = await getCurrentBranch(environment.workspace);

    /// 查询最新的打包配置
    /// 查询最新的打包版本配置
    final config = await appwriteServer.getCurrentBranchBuildConfig(
      databaseId: environment.appwriteBuildEnvironment.databaseId,
      buildConfigCollectionId:
          environment.appwriteBuildEnvironment.buildConfigCollectionId,
      platform: environment.platform,
      buildName: environment.buildName,
      melosBranch: melosBranch,
      unityBranch: environment.unityBranchName,
    );

    /// 上一次打包Unity工程的Commit id
    String? buildUnityCommitId = config?.data['unity_commit_id'];

    /// 上一次打包Unity工程的Build Version Id
    String? buildUnityBuildVersionId = config?.data['unity_build_version'];

    /// 本地打包的Flutter Git更新日志
    StringBuffer flutterLogBuffer = StringBuffer();

    /// 本地打包的Unity Git更新日志
    StringBuffer unityLogBuffer = StringBuffer();

    /// 更新Unity工程并且获取Unity的更新日志
    String unityWorkspace = switch (environment.platform) {
      'ios' => unityEnvironment.iosUnityWorkspace,
      'android' => unityEnvironment.androidUnityWorkspace,
      _ => throw Exception('不支持的平台'),
    };

    /// 切换Unity为对应分支
    await switchBranch(unityWorkspace, environment.unityBranchName);

    /// 获取当前Unity工程的Commit id
    final currentUnityCommitId = await getCurrentCommitHash(unityWorkspace);

    /// 获取当前的Build Version Id
    final currentUnityBuildVersionId =
        await getUnityBuildVersion(unityWorkspace);

    /// 最新打包Unity工程的Commit id
    String afterCommitId = currentUnityCommitId;

    /// 如果build version没有发生变化 则使用之前的commit id
    if (buildUnityBuildVersionId == "$currentUnityBuildVersionId") {
      afterCommitId = buildUnityCommitId ?? currentUnityCommitId;
    } else {
      isUnityBuild = true;
    }

    /// 获取当前Unity工程的变更日志
    final unityChangeLog = await GetGitLog(
      root: unityWorkspace,
      beforeCommitId: buildUnityCommitId ?? currentUnityCommitId,
      afterCommitId: afterCommitId,
    ).get();

    unityLogBuffer.writeln('''
[Unity][${environment.unityBranchName}][$currentUnityCommitId]:
$unityChangeLog
''');

    /// 上一次打包Flutter模块的分支和节点配置
    DocumentList? buildBranchConfig;

    if (config != null) {
      buildBranchConfig = await appwriteServer.queryBuildBranchConfig(
        databaseId: environment.appwriteBuildEnvironment.databaseId,
        buildBranchConfigCollectionId:
            environment.appwriteBuildEnvironment.buildBranchConfigCollectionId,
        buildId: config.$id,
      );
    }

    /// 将submodule代码切换到对应的分支（可能存在多余）
    for (var submodule in gitSubmodules) {
      final branch = submodule.branch;
      final path = submodule.path;
      final name = submodule.name;
      if (name == null) {
        throw Exception("submodule name is null");
      }
      if (branch == null) {
        throw Exception("[${submodule.name}]submodule branch is null");
      }
      if (path == null) {
        throw Exception("[${submodule.name}]submodule path is null");
      }
      final submodulePath = join(environment.workspace, path);
      await switchBranch(submodulePath, branch);

      /// 获取之前打包的Commit id
      String? buildCommitId;
      if (buildBranchConfig != null) {
        final buildBranchConfigData = buildBranchConfig.documents
            .where((element) => element.data['path'] == path)
            .where((element) => element.data['branch'] == branch)
            .lastOrNull;
        buildCommitId = buildBranchConfigData?.data['commit_id'];
      }

      /// 获取当前submodule的Commit id
      final currentCommitId = await getCurrentCommitHash(submodulePath);

      /// 获取当前submodule的变更日志
      final changeLog = await GetGitLog(
        root: submodulePath,
        beforeCommitId: buildCommitId ?? currentCommitId,
        afterCommitId: currentCommitId,
      ).get();

      flutterLogBuffer.writeln('''
[$name][$branch][$currentCommitId]:
$changeLog
''');

      if (buildCommitId != currentCommitId) {
        isFlutterBuild = true;
      }

      buildBranchConfigs.add(AppwriteBuildBranchConfig(
        path: path,
        branch: branch,
        commitHash: currentCommitId,
      ));
    }

    /// 执行melos bootstrap
    await buildAppRunner.runProcess(
      [
        'melos',
        "bootstrap",
      ],
      workingDirectory: Directory(environment.workspace),
      printOutput: true,
    );

    final formatChangeLog = formatGitLog(
      flutterLogBuffer.toString(),
      unityLogBuffer.toString(),
    );
    final changeLog = '''
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

    loggerDebug(
        '[isFlutterBuild:$isFlutterBuild][isUnityBuild:$isUnityBuild][forceBuild:${environment.forceBuild}]');
    if (!isFlutterBuild && !isUnityBuild && !environment.forceBuild) {
      loggerSuccess('检测当前打包版本和上次打包版本一致，不需要进行打包！如果强制打包请设置FORCE_BUILD=true');
      return;
    }

    loggerDebug('开始复制Unity静态库到指定位置');
    await copyUnityStaticLibrary(currentUnityBuildVersionId, environment);

    final flutterCurrentCommitId = await getCurrentCommitHash(
      join(environment.workspace, 'metaapp_flutter'),
    );
    final flutterBranch = await getCurrentBranch(
      join(environment.workspace, 'metaapp_flutter'),
    );

    loggerDebug('开始复制Flutter静态库到指定位置');
    await copyFlutterStaticLibrary(
        flutterCurrentCommitId, environment, isFlutterBuild, flutterBranch);

    final isInitFlutterEnvironment =
        argResults?['initFlutterEnvironment'] == 'true';
    if (isInitFlutterEnvironment) {
      /// 开始初始化Flutter环境
      await initFlutterEnvironment(
        appHomeDir: appHomeDir,
        buildType: buildType,
        configuration: 'release',
        isStore: environment.isStore,
        androidChannel: environment.androidChannel,
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
    await copyIpaOrApkToBuildDir(environment, copyDir);

    if (environment.upload) {
      loggerDebug('开始上传ipa/apk......');
      final uploadLog =
          '[Tag:${environment.tag}][Flutter($melosBranch)][Unity(${environment.unityBranchName})] ';
      await uploadApp(
        log: '$uploadLog 新版本发布了，请下载体验!',
        environment: environment,
      );
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
      buildConfigCollectionId:
          environment.appwriteBuildEnvironment.buildConfigCollectionId,
      buildBranchConfigCollectionId:
          environment.appwriteBuildEnvironment.buildBranchConfigCollectionId,
      platform: environment.platform,
      buildName: environment.buildName,
      melosBranch: melosBranch,
      unityBranch: environment.unityBranchName,
      unityCommitId: afterCommitId,
      buildNumber: int.parse(environment.buildNumber),
      unityBuilderVersion: currentUnityBuildVersionId.toString(),
      buildBranchConfigs: buildBranchConfigs,
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
    ).run().catchError((e) {
      loggerError('上传sentry符号失败:${e.toString()}');
    });
  }

  /// 复制Unity静态库到指定位置
  Future<void> copyUnityStaticLibrary(
      int buildVersionId, UploadAppEnvironment environment) async {
    final appRunner = await createAppRunner(appHomeDir);

    /// 删除之前的缓存
    final cacheDir = switch (environment.platform) {
      'ios' => Directory(join(appHomeDir.iosDir.path, 'frameworks', 'unity')),
      'android' => Directory(join(appHomeDir.androidDir.path, 'aar', 'unity')),
      _ => throw Exception('不支持的平台:${environment.platform}')
    };
    if (cacheDir.existsSync()) {
      cacheDir.deleteSync(recursive: true);
    }

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
        isUseCache ? '--isUseCache' : '--no-isUseCache',
      ],
      printOutput: true,
    );
  }

  Future<void> copyFlutterStaticLibrary(
    String commitHash,
    UploadAppEnvironment environment,
    bool needUpdateCache,
    String flutterBranch,
  ) async {
    final cacheDir = switch (environment.platform) {
      'ios' => Directory(join(
          appHomeDir.iosDir.path,
          'frameworks',
          'flutter',
        )),
      'android' => Directory(join(
          appHomeDir.androidDir.path,
          'aar',
          'flutter',
        )),
      _ => throw Exception('不支持的平台:${environment.platform}')
    };
    if (cacheDir.existsSync()) {
      cacheDir.deleteSync(recursive: true);
    }
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
        flutterBranch,
        '--commitHash',
        commitHash,
        getUseMockCommand(),
        isUseCache && !needUpdateCache ? '--isUseCache' : '--no-isUseCache',
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
  Future<void> copyIpaOrApkToBuildDir(
    UploadAppEnvironment environment,
    String? copyDir,
  );

  /// 发送日志
  Future<void> sendLog({
    required String log,
    required UploadAppEnvironment environment,
  });

  /// 通过交互获取环境变量
  Future<UploadAppEnvironment> chooseEnvironment(
      UnityEnvironment unityEnvironment) async {
    final melosBranch = ArgumentGet(argResults).getString(
      'branch',
      '请选择Melos分支',
      allowed: await getLatestBranchList(appHomeDir.workspace),
    );
    final buildName = ArgumentGet(argResults).getString('buildName', '请输入版本号');
    final unityBranch = ArgumentGet(argResults).getString(
      'unityBranch',
      '请选择Unity分支',
      allowed: await getLatestBranchList(
        unityEnvironment.getPlatfromUnityWorkspace(platform),
      ),
    );
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
    String androidChannel = 'Winner';
    String zealotChannelKey = readBuildAppEnv('ZEALOT_CHANNEL_KEY', appHomeDir);
    if (platform == 'android') {
      if (isStore == 'true') {
        final zealotChannel = ArgumentGet(argResults).getString(
          'zealotChannel',
          '请选择Zealot渠道',
          allowed: [
            'Winner',
            'Tencent',
            'Huawei',
            'Xiaomi',
            'Oppo',
            'Meizu',
            'Vivo',
            'Honor',
            'Samsung',
          ],
        );
        androidChannel = zealotChannel;
        final keys = {
          'Winner': environmentMap['WINNER_ZEALOT_CHANNEL_KEY']!,
          'Tencent': environmentMap['TENCENT_ZEALOT_CHANNEL_KEY']!,
          'Huawei': environmentMap['HUAWEI_ZEALOT_CHANNEL_KEY']!,
          'Xiaomi': environmentMap['XIAOMI_ZEALOT_CHANNEL_KEY']!,
          'Oppo': environmentMap['OPPO_ZEALOT_CHANNEL_KEY']!,
          'Meizu': environmentMap['MEIZU_ZEALOT_CHANNEL_KEY']!,
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
      forceBuild: forceBuild == 'true',
      melosBranch: melosBranch,
      unityBranchName: unityBranch,
      upload: upload == 'true',
      sendLog: sendLog == 'true',
      isStore: isStore == 'true',
      appHomeDir: appHomeDir,
      unityEnvironment: unityEnvironment,
      zealotChannelKey: zealotChannelKey,
      androidChannel: androidChannel,
    );
  }
}
