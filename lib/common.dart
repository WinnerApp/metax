import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:color_logger/color_logger.dart';
import 'package:dio/dio.dart';
import 'package:meta_tool/app_home_dir.dart';
import 'package:meta_tool/define.dart';
import 'package:path/path.dart';
import 'package:process_runner/process_runner.dart';

/// 判断是否是git仓库
Future<bool> isGitRepository(String workingDirectory) async {
  final commands = ['git', 'rev-parse', '--is-inside-work-tree'];
  return ProcessRunner(defaultWorkingDirectory: Directory(workingDirectory))
      .runProcess(commands, printOutput: true)
      .then((e) => e.output.trim() == 'true');
}

/// clone仓库
Future<void> cloneRepository(String workingDirectory, String url) async {
  final commands = ['git', 'clone', url, workingDirectory];
  await ProcessRunner().runProcess(commands, printOutput: true);
}

Future<void> pullAndSwitchBranch(String workingDirectory, String branch) async {
  final switchBranch = getBranchName(branch);
  await ProcessRunner().runProcess(
    [
      'git',
      'reset',
      '--hard',
    ],
    workingDirectory: Directory(workingDirectory),
    printOutput: true,
  );
  await ProcessRunner().runProcess(
    [
      'git',
      'fetch',
      'origin',
    ],
    workingDirectory: Directory(workingDirectory),
    printOutput: true,
  );

  await ProcessRunner().runProcess(
    [
      'git',
      'switch',
      switchBranch,
    ],
    workingDirectory: Directory(workingDirectory),
    printOutput: true,
  );
  await ProcessRunner().runProcess(
    [
      'git',
      'reset',
      '--hard',
      'origin/$switchBranch',
    ],
    workingDirectory: Directory(workingDirectory),
    printOutput: true,
  );
  await ProcessRunner().runProcess(
    [
      'git',
      'lfs',
      'pull',
      'origin',
      switchBranch,
    ],
    workingDirectory: Directory(workingDirectory),
    printOutput: true,
  );
}

/// 获取当前的分支名称
Future<String> getCurrentBranch(String workingDirectory) async {
  final commands = ['git', 'rev-parse', '--abbrev-ref', 'HEAD'];
  return ProcessRunner(defaultWorkingDirectory: Directory(workingDirectory))
      .runProcess(commands, printOutput: true)
      .then((result) => result.stdout.trim());
}

/// 获取最新分支列表
Future<Set<String>> getLatestBranchList(String workingDirectory) async {
  await ProcessRunner().runProcess(
    [
      'git',
      'fetch',
      'origin',
    ],
    workingDirectory: Directory(workingDirectory),
    printOutput: true,
  );
  await ProcessRunner().runProcess(
    [
      'git',
      'remote',
      'prune',
      'origin',
    ],
    workingDirectory: Directory(workingDirectory),
    printOutput: true,
  );
  final commands = ['git', 'branch', '-r'];
  return ProcessRunner(defaultWorkingDirectory: Directory(workingDirectory))
      .runProcess(commands, printOutput: true)
      .then((result) => result.stdout.trim().split('\n'))
      .then((e) => e.map((e) => getBranchName(e)).toSet());
}

/// 切换分支
Future<void> switchBranch(String workingDirectory, String branch) async {
  final switchBranch = getBranchName(branch);
  final currentBranch = await getCurrentBranch(workingDirectory);
  await ProcessRunner().runProcess(
    [
      'git',
      'fetch',
      'origin',
    ],
    workingDirectory: Directory(workingDirectory),
    printOutput: true,
  );
  await ProcessRunner().runProcess(
    [
      'git',
      'clean',
      '-df',
    ],
    workingDirectory: Directory(workingDirectory),
    printOutput: true,
  );
  await ProcessRunner().runProcess(
    [
      'git',
      'reset',
      '--hard',
      'origin/$switchBranch',
    ],
    workingDirectory: Directory(workingDirectory),
    printOutput: true,
  );
  if (switchBranch != currentBranch) {
    await ProcessRunner().runProcess(
      [
        'git',
        'switch',
        switchBranch,
      ],
      workingDirectory: Directory(workingDirectory),
      printOutput: true,
    );
  }
  await ProcessRunner().runProcess(
    [
      'git',
      'pull',
      'origin',
      switchBranch,
    ],
    workingDirectory: Directory(workingDirectory),
    printOutput: true,
  );
  if (await getCurrentBranch(workingDirectory) != switchBranch) {
    throw '切换分支$switchBranch失败';
  }
}

String getBranchName(String branch) {
  return branch.split('/').last;
}

/// 获取当前的commit hash
Future<String> getCurrentCommitHash(String workingDirectory) async {
  final commands = ['git', 'rev-parse', 'HEAD'];
  return ProcessRunner(defaultWorkingDirectory: Directory(workingDirectory))
      .runProcess(commands, printOutput: true)
      .then((result) => result.stdout.trim());
}

/// 获取指定Commit Hash的提交时间
Future<DateTime> getCommitTime(
    String workingDirectory, String commitHash) async {
  final commands = ['git', 'show', '-s', '--format=%ci', commitHash];
  return ProcessRunner(defaultWorkingDirectory: Directory(workingDirectory))
      .runProcess(commands, printOutput: true)
      .then((result) => DateTime.parse(result.stdout.trim()));
}

String readEnv(
  String envName, {
  Map<String, String>? environment,
  String? throwMessage,
}) {
  Map<String, String> readEnv = {...Platform.environment};
  if (environment != null) {
    readEnv.addAll(environment);
  }
  if (!readEnv.keys.contains(envName)) {
    String message = "请设置环境变量 【$envName】";
    if (throwMessage != null) {
      message += " $throwMessage";
    }
    throw message;
  }
  return readEnv[envName]!;
}

String readAppEnv(String envName, AppHomeDir appHomeDir) {
  final environment = loadAppEnvironment(appHomeDir);
  return readEnv(
    envName,
    environment: environment,
    throwMessage: '请先执行metax init app_environment',
  );
}

String readBuildAppEnv(String envName, AppHomeDir appHomeDir,
    {Map<String, String>? environment}) {
  environment ??= loadBuildAppEnvironment(appHomeDir, false);
  return readEnv(
    envName,
    environment: environment,
    throwMessage: '请先配置打包的环境变量',
  );
}

void checkEnv(String envName, {Map<String, String>? environment}) {
  Map<String, String> readEnv = {...Platform.environment};
  if (environment != null) {
    readEnv.addAll(environment);
  }
  if (!readEnv.keys.contains(envName)) {
    throw "请设置环境变量 【$envName】";
  }
}

/// 检测命令是否安装
Future<bool> isCommandInstall(String name) async {
  return ProcessRunner()
      .runProcess(['which', name], printOutput: true)
      .then((e) => !e.output.contains('$name not found'))
      .catchError((e) => false);
}

/// 如果文件夹存在则删除
Future<void> deleteDirIfExists(String path) async {
  if (Directory(path).existsSync()) {
    await Directory(path).delete(recursive: true);
  }
}

/// 复制文件
Future<void> copyFile(File source, File target,
    {bool allowDelete = true}) async {
  if (target.existsSync()) {
    if (allowDelete) {
      await target.delete();
    } else {
      throw '文件已存在: ${target.path}';
    }
  }
  await target.create(recursive: true);
  await source.copy(target.path).catchError((e) async {
    await target.delete();
    throw '复制文件失败: ${source.path} -> ${target.path}';
  });
}

/// 创建文件并且写入内容
Future<void> createFileAndWrite(File file, String content) async {
  if (!await file.exists()) {
    await file.create(recursive: true);
  }
  await file.writeAsString(content).catchError((e) async {
    await file.delete();
    throw '写入文件失败: ${file.path}';
  });
}

void loggerSuccess(String message) {
  logger.log(message, status: LogStatus.success);
}

void loggerError(String message) {
  logger.log(message, status: LogStatus.error);
}

void loggerWarning(String message) {
  logger.log(message, status: LogStatus.warning);
}

void loggerInfo(String message) {
  logger.log(message, status: LogStatus.info);
}

void loggerDebug(String message) {
  logger.log(message, status: LogStatus.debug);
}

/// 获取当前Unity工程的build_version.txt文件内容
Future<int> getUnityBuildVersion(String workingDirectory) async {
  final buildVersionFile = File(join(workingDirectory, 'build_version.txt'));
  if (!await buildVersionFile.exists()) {
    throw '$buildVersionFile文件不存在';
  }
  int? buildVersionId =
      await buildVersionFile.readAsString().then((e) => int.tryParse(e));
  if (buildVersionId == null) {
    throw 'Unity工程的build_version.txt文件内容不是有效的数字';
  }
  return buildVersionId;
}

/// 复制zip 到指定目录下面并先清空当前目录
Future<void> copyZipToDir(String zipPath, Directory targetDir) async {
  if (await targetDir.exists()) {
    await targetDir.delete(recursive: true);
  }
  await targetDir.create(recursive: true);
  await ProcessRunner().runProcess(
    [
      'unzip',
      '-o',
      zipPath,
      '-d',
      targetDir.path,
    ],
    printOutput: true,
  );
}

String formatGitLog(String flutterLog, String unityLog) {
  List<String> filterLogs(String log) {
    List<String> logs = [];
    for (var log in log.split("\n")) {
      /// 如果当前行存在以下关键字 则忽略
      if (['commit', 'Author', 'Date', 'Merge', '# Conflicts', '#    ']
          .any((e) => log.toLowerCase().startsWith(e.toLowerCase()))) {
        continue;
      }
      logs.add(log);
    }
    return logs;
  }

  List<String> logs = [];
  final flutterLogs = filterLogs(flutterLog);
  final unityLogs = filterLogs(unityLog);
  if (flutterLogs.length + unityLogs.length > 100) {
    logs.addAll(unityLogs.sublist(0, min(unityLogs.length, 30)));
    logs.addAll(flutterLogs.sublist(0, min(flutterLogs.length, 30)));
  } else {
    logs.addAll(unityLogs);
    logs.addAll(flutterLogs);
  }
  return logs.join('\n');
}

/// 发送文本到企业微信
Future<bool> sendTextToWeixinWebhooks(String text, String hookUrl) async {
  final dio = Dio();
  final response = await dio.post(
    hookUrl,
    options: Options(headers: {
      'Content-Type': 'application/json',
    }),
    data: json.encode({
      'msgtype': 'text',
      'text': {'content': text},
    }),
  );

  final status = response.statusCode;
  if (status != 200) {
    loggerError('企业微信发送失败:${response.statusMessage}');
    return false;
  }
  return true;
}

/// 上传对应的缓存资源
Future<void> uploadCacheResource({
  required BuildPlatform buildPlatform,
  required BuildLibrary buildLibrary,
  required BuildConfiguration buildConfiguration,
  required BuildType buildType,
  required String branch,
  required String commitHash,
  required DateTime commitTime,
  required int buildId,
}) async {
  await ProcessRunner().runProcess(
    [
      'metax',
      'cache',
      'upload',
      '--buildPlatform',
      buildPlatform.name,
      '--buildLibrary',
      buildLibrary.name,
      '--buildConfiguration',
      buildConfiguration.name,
      '--buildType',
      buildType.name,
      '--branch',
      branch,
      '--commitHash',
      commitHash,
      '--commitTime',
      commitTime.toUtc().toIso8601String(),
      '--buildId',
      buildId.toString(),
    ],
    printOutput: true,
    workingDirectory: Directory(appHomeDir.workspace),
  );
}

/// 使用缓存
Future<void> useCache({
  required String workspace,
  required BuildPlatform buildPlatform,
  required BuildLibrary buildLibrary,
  required BuildConfiguration buildConfiguration,
  required BuildType buildType,
  required String branch,
  required String commitHash,
  int buildId = 0,
}) async {
  await ProcessRunner().runProcess(
    [
      'metax',
      'cache',
      'use',
      '--workspace',
      workspace,
      '--buildPlatform',
      buildPlatform.name,
      '--buildLibrary',
      buildLibrary.name,
      '--buildConfiguration',
      buildConfiguration.name,
      '--buildType',
      buildType.name,
      '--branch',
      branch,
      '--commitHash',
      commitHash,
      '--buildId',
      buildId.toString(),
    ],
    printOutput: true,
  );
}

/// 下载对应的缓存资源
Future<void> downloadCacheResource({
  required String workspace,
  required BuildPlatform buildPlatform,
  required BuildLibrary buildLibrary,
  required BuildConfiguration buildConfiguration,
  required BuildType buildType,
  required String branch,
  required String commitHash,
  int buildId = 0,
}) async {
  loggerDebug('下载缓存到本地中，请稍等......');
  await ProcessRunner().runProcess(
    [
      'metax',
      'cache',
      'download',
      '--buildPlatform',
      buildPlatform.name,
      '--buildLibrary',
      buildLibrary.name,
      '--buildConfiguration',
      buildConfiguration.name,
      '--buildType',
      buildType.name,
      '--branch',
      branch,
      '--buildId',
      buildId.toString(),
      '--commitHash',
      commitHash,
    ],
    printOutput: true,
  );
  loggerSuccess('下载缓存成功');
}

/// 获取缓存资源存放的目录
Directory getCacheResourceDir(String workspace) {
  return Directory(join(workspace, 'cache'));
}

/// 生成Flutter环境参数
Future<void> generateFlutterEnv(String workspace) async {
  throw UnimplementedError();
}

/// 获取当前时间戳
int getCurrentTimestamp() {
  return DateTime.now().millisecondsSinceEpoch ~/ 1000;
}

Future<void> writeEnvironmentValueInFile(
  String filePath,
  String key,
  String value,
) async {
  final file = File(filePath);
  final environmentContent = '$key=$value';
  if (!await file.exists()) {
    await file.create(recursive: true);
    await file.writeAsString(environmentContent);
  } else {
    final contents = await file.readAsLines().then((e) => e.map((e) {
          if (e.startsWith('$key=')) {
            return environmentContent;
          }
          return e;
        }).toList());
    await file.writeAsString(contents.join('\n'));
  }
}

/// 从文件读取设置的环境
Map<String, String> readEnvironmentFromFile(String filePath) {
  Map<String, String> environment = {};
  final file = File(filePath);
  if (!file.existsSync()) {
    return environment;
  }
  final contents = file.readAsLinesSync();
  for (var line in contents) {
    final match = RegExp(r'(\w+)=(\S+)').firstMatch(line);
    if (match != null) {
      environment[match.group(1)!] = match.group(2)!;
    }
  }
  return environment;
}

Map<String, String> loadAppEnvironment(AppHomeDir appHomeDir) {
  final appEnvFile = File(join(
    appHomeDir.workspace,
    'jenkins_ci',
    'env',
    'app',
    '.env',
  ));
  if (!appEnvFile.existsSync()) {
    throw '请使用metax init app_environment 初始化环境变量';
  }
  final environment = readEnvironmentFromFile(appEnvFile.path);
  final appWriteEnvFile = File(join(
    appHomeDir.workspace,
    'jenkins_ci',
    'env',
    'appwrite',
    '.env',
  ));
  if (!appWriteEnvFile.existsSync()) {
    throw '${appWriteEnvFile.path}文件不存在';
  }
  environment.addAll(readEnvironmentFromFile(appWriteEnvFile.path));
  if (customUnityPath != null) {
    if (Platform.isMacOS) {
      environment['UNITY_ENGINE_PATH'] = join(
        customUnityPath!,
        'Contents',
        'MacOS',
        'Unity',
      );
    } else {
      throw UnimplementedError('暂未支持非MacOS环境');
    }
  }
  return environment;
}

Map<String, String> loadBuildAppEnvironment(
    AppHomeDir appHomeDir, bool isStore) {
  final environment = loadAppEnvironment(appHomeDir);
  // jenkins_ci/env/build_app/common/.env
  final commonEnvFile = File(join(
    appHomeDir.workspace,
    'jenkins_ci',
    'env',
    'build_app',
    'common',
    '.env',
  ));
  if (commonEnvFile.existsSync()) {
    environment.addAll(readEnvironmentFromFile(commonEnvFile.path));
  }
  if (isStore) {
    final releaseEnvFile = File(join(
      appHomeDir.workspace,
      'jenkins_ci',
      'env',
      'build_app',
      'release',
      '.env',
    ));
    if (releaseEnvFile.existsSync()) {
      environment.addAll(readEnvironmentFromFile(releaseEnvFile.path));
    }
  } else {
    final debugEnvFile = File(join(
      appHomeDir.workspace,
      'jenkins_ci',
      'env',
      'build_app',
      'debug',
      '.env',
    ));
    if (debugEnvFile.existsSync()) {
      environment.addAll(readEnvironmentFromFile(debugEnvFile.path));
    }
  }
  return environment;
}

Future<ProcessRunner> createAppRunner(AppHomeDir appHomeDir) async {
  final environment = loadAppEnvironment(appHomeDir);
  return ProcessRunner(
    defaultWorkingDirectory: Directory(appHomeDir.workspace),
    environment: environment,
  );
}

Future<ProcessRunner> createBuildAppRunner(
    AppHomeDir appHomeDir, bool isStore) async {
  final environment = loadBuildAppEnvironment(appHomeDir, isStore);
  return ProcessRunner(
    defaultWorkingDirectory: Directory(appHomeDir.workspace),
    environment: environment,
  );
}

/// 检测安卓NDK是否存在
Future<void> checkAndroidNDK(AppHomeDir appHomeDir) async {
  final localPropertyFile = File(join(
    appHomeDir.androidDir.path,
    'local.properties',
  ));
  if (!localPropertyFile.existsSync()) {
    throw '${localPropertyFile.path}文件不存在';
  }
  final environment = readEnvironmentFromFile(localPropertyFile.path);
  final ndkDir = environment['ndk.dir'];
  if (ndkDir == null) {
    throw '请先通过metax init android_environment 初始化安卓环境ndk.dir变量';
  }
  final ndkBuild = File(join(ndkDir, 'ndk-build'));
  if (!ndkBuild.existsSync()) {
    throw 'ndk.dir路径错误，请检查是否正确！';
  }
}

/// 复制目录到指定目录
Future<void> copyDirToDir(Directory sourceDir, Directory targetDir) async {
  if (await targetDir.exists()) {
    await targetDir.delete(recursive: true);
  }
  final targetParentDir = targetDir.parent;
  if (!await targetParentDir.exists()) {
    await targetParentDir.create(recursive: true);
  }
  await ProcessRunner().runProcess(
    [
      'cp',
      '-rf',
      sourceDir.path,
      targetDir.path,
    ],
    printOutput: true,
  );
}

String getUseMockCommand() {
  return useMock ? '--isUseMock' : '--no-isUseMock';
}

/// 获取Flutter命令路径
Future<String> getFlutterCommandDir(AppHomeDir appHomeDir) async {
  final flutterBinPath = await ProcessRunner().runProcess(
    ['which', 'flutter'],
    printOutput: true,
  ).then((e) => e.output.split('\n').first.trim());
  return File(flutterBinPath).parent.parent.path;
}

/// 初始化Flutter环境
Future<void> initFlutterEnvironment({
  required AppHomeDir appHomeDir,
  required String buildType,
  required String configuration,
  required bool isStore,
  required String androidChannel,
}) async {
  await ProcessRunner().runProcess(
    [
      'metax',
      'init',
      'flutter_environment',
      '--buildType',
      buildType,
      '--configuration',
      configuration,
      isStore ? '--isStore' : '--no-isStore',
      '--androidChannel',
      androidChannel,
    ],
    workingDirectory: appHomeDir.directory,
    printOutput: true,
  );
}

/// 设置版本号
Future<void> setVersionNumber({
  required String buildName,
  required String buildNumber,
  required String platform,
}) async {
  await ProcessRunner().runProcess(
    [
      'metax',
      'init',
      'build_name_number',
      '--platform',
      platform,
      '--buildName',
      buildName,
      '--buildNumber',
      buildNumber,
    ],
    workingDirectory: appHomeDir.directory,
    printOutput: true,
  );
}
