import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:color_logger/color_logger.dart';
import 'package:dio/dio.dart';
import 'package:meta_tool/app_home_dir.dart';
import 'package:meta_tool/define.dart';
import 'package:meta_tool/flutter_sdk.dart';
import 'package:meta_tool/flutter_web_version_data.dart';
import 'package:meta_tool/git_submodule_parse.dart';
import 'package:path/path.dart';
import 'package:process_runner/process_runner.dart';

/// 更新 Flutter 侧的 `assets/dart_define.json` 配置。
///
/// - 该文件通常由 `flutter pub run dart_define generate` 生成。
/// - 这里会在原有 JSON 基础上覆盖/写入关键字段。
/// - 若文件不存在将直接抛错（由调用方决定是否先生成）。
Future<void> updateDartDefineJsonFile({
  required File dartDefineJsonFile,
  required bool isStore,
  required String androidChannel,
  required Map branchConfig,
}) async {
  if (!dartDefineJsonFile.existsSync()) {
    throw ArgumentError('dart_define.json文件不存在(${dartDefineJsonFile.path})');
  }

  final raw = await dartDefineJsonFile.readAsString();
  final decoded = jsonDecode(raw);
  final Map<String, dynamic> json = decoded is Map<String, dynamic>
      ? decoded
      : <String, dynamic>{};

  bool debugInvertOversizedImages = false;
  bool isOpenDioLog = true;
  bool debugYunDun = false;
  bool enableLog = true;
  bool showRestoreParams = false;
  bool isStoreVersion = false;
  String environment = 'sit';
  String channel = androidChannel;
  bool enableFlutterError = false;
  bool enableUnityOpenTime = false;
  bool enableSensorsLog = false;

  if (isStore) {
    isStoreVersion = true;
    environment = 'release';
  }

  json['debugInvertOversizedImages'] = debugInvertOversizedImages;
  json['isOpenDioLog'] = isOpenDioLog;
  json['debugYunDun'] = debugYunDun;
  json['enableLog'] = enableLog;
  json['showRestoreParams'] = showRestoreParams;
  json['isStoreVersion'] = isStoreVersion;
  json['environment'] = environment;
  json['androidChannel'] = channel;
  json['enableFlutterError'] = enableFlutterError;
  json['enableUnityOpenTime'] = enableUnityOpenTime;
  json['enableSensorsLog'] = enableSensorsLog;
  if (branchConfig.isNotEmpty) {
    json['branchConfig'] = branchConfig;
  }

  loggerDebug('当前最新的Flutter环境配置:');
  for (final key in json.keys) {
    loggerDebug('$key: ${json[key]}');
  }

  await dartDefineJsonFile
      .writeAsString(JsonEncoder.withIndent('  ').convert(json));
}

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
/// 功能：
/// 1. 获取最新远程分支信息
/// 2. 丢弃所有已跟踪文件的本地更改
/// 3. 切换到目标分支并拉取最新代码
Future<void> switchBranch(String workingDirectory, String branch) async {
  final switchBranch = getBranchName(branch);
  final currentBranch = await getCurrentBranch(workingDirectory);

  // 步骤1: 先 fetch 获取最新远程分支信息
  loggerDebug('获取最新远程分支信息...');
  await ProcessRunner().runProcess(
    [
      'git',
      'fetch',
      'origin',
    ],
    workingDirectory: Directory(workingDirectory),
    printOutput: true,
  );

  // 步骤2: 如果目标分支和当前分支不同，先切换到目标分支
  if (switchBranch != currentBranch) {
    loggerDebug('切换到分支: $switchBranch');
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

  // 步骤3: 丢弃所有已跟踪文件的本地更改，重置到远程分支状态
  loggerDebug('丢弃所有已跟踪文件的本地更改，重置到远程分支状态...');
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

  // 步骤4: 拉取最新代码（确保是最新的）
  loggerDebug('拉取最新代码...');
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

  // 验证分支切换是否成功
  final finalBranch = await getCurrentBranch(workingDirectory);
  if (finalBranch != switchBranch) {
    throw '切换分支$switchBranch失败，当前分支为: $finalBranch';
  }

  loggerSuccess('成功切换到分支: $switchBranch');
}

/// 对齐 Melos 工作区到指定执行分支（与打包流程一致）：
/// 1. 主仓切到 [melosBranch] 并拉最新
/// 2. 重置已有子模块到其当前分支 tip
/// 3. 执行 `init_git_submodule.sh`
/// 4. 各子模块切到配置分支（`MAIN_BRANCH` 跟随主仓）并拉最新
Future<void> syncMelosWorkspaceToBranch(
  String workspace,
  String melosBranch,
) async {
  await switchBranch(workspace, melosBranch);

  /// 0. 重置所有已存在的子模块到当前分支的最新提交
  final gitSubmodulePath = await getGitmodulesFilePath(workspace);
  if (await File(gitSubmodulePath).exists()) {
    final existingSubmodules = await parseGitmodulesFile(gitSubmodulePath);
    for (final submodule in existingSubmodules) {
      final path = submodule.path;
      if (path == null) {
        continue;
      }
      final submodulePath = join(workspace, path);
      final submoduleGitDir = join(submodulePath, '.git');

      if (await Directory(submodulePath).exists() &&
          (await Directory(submoduleGitDir).exists() ||
              await File(submoduleGitDir).exists())) {
        try {
          final currentBranch = await getCurrentBranch(submodulePath);
          loggerDebug('重置子模块 [$path] 从分支 [$currentBranch] 到最新提交');
          await switchBranch(submodulePath, currentBranch);
        } catch (e) {
          loggerWarning('重置子模块 [$path] 失败: $e');
        }
      }
    }
  }

  /// 1. 更新最新的 Git submodule
  await ProcessRunner().runProcess(
    [
      'bash',
      'init_git_submodule.sh',
    ],
    workingDirectory: Directory(workspace),
    printOutput: true,
  );

  /// 2. 将 submodule 切换到对应执行分支最新
  final gitSubmodules = await parseGitmodulesFile(gitSubmodulePath);
  final currentMelosBranch = await getCurrentBranch(workspace);

  for (final submodule in gitSubmodules) {
    final rawBranch = submodule.branch;
    final path = submodule.path;
    final name = submodule.name;
    if (name == null) {
      throw Exception('submodule name is null');
    }
    if (rawBranch == null) {
      throw Exception('[$name]submodule branch is null');
    }
    if (path == null) {
      throw Exception('[$name]submodule path is null');
    }
    final branch = getBranchName(rawBranch, mainBranch: currentMelosBranch);
    final submodulePath = join(workspace, path);
    await switchBranch(submodulePath, branch);
  }
}

/// 解析分支名。
///
/// - 去掉 `origin/` 等远程前缀
/// - 若为 `MAIN_BRANCH` / `$MAIN_BRANCH`，则替换为主项目分支 [mainBranch]
String getBranchName(String branch, {String? mainBranch}) {
  final name = branch.split('/').last;
  final placeholder = name.startsWith(r'$') ? name.substring(1) : name;
  if (placeholder == 'MAIN_BRANCH') {
    if (mainBranch == null || mainBranch.isEmpty) {
      throw Exception('分支为 \$MAIN_BRANCH，但未提供主项目分支名称');
    }
    return getBranchName(mainBranch);
  }
  return name;
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

String readBuildAppEnv(
  String envName,
  AppHomeDir appHomeDir, {
  Map<String, String>? environment,
  bool isStore = false,
}) {
  environment ??= loadBuildAppEnvironment(appHomeDir, isStore);
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
  String buildVersion = await buildVersionFile.readAsString();
  buildVersion = buildVersion.trim().replaceAll('%', '');
  int? buildVersionId = int.tryParse(buildVersion);
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

/// iOS Flutter framework 缓存解压后对齐 podspec（Measure -> measure-sh 等）
Future<void> alignIosFlutterFrameworkPodspecs({
  required AppHomeDir appHomeDir,
  required String buildConfiguration,
}) async {
  final script = File(join(
    appHomeDir.workspace,
    'jenkins_ci',
    'setup_ios_framework_podspec.sh',
  ));
  if (!await script.exists()) {
    loggerDebug('跳过 podspec 对齐：${script.path} 不存在');
    return;
  }

  final configuration = buildConfiguration == BuildConfiguration.release.name
      ? 'Release'
      : 'Debug';
  final frameworkDir = join(
    appHomeDir.iosDir.path,
    'frameworks',
    'flutter',
    configuration,
  );
  if (!Directory(frameworkDir).existsSync()) {
    loggerDebug('跳过 podspec 对齐：$frameworkDir 不存在');
    return;
  }

  loggerDebug('对齐 iOS Flutter framework podspec: $configuration');
  await ProcessRunner().runProcess(
    [
      'bash',
      script.path,
      configuration,
      frameworkDir,
    ],
    workingDirectory: Directory(appHomeDir.workspace),
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
  final response = await dio
      .post(
    hookUrl,
    options: Options(headers: {
      'Content-Type': 'application/json',
    }),
    data: json.encode({
      "msg_type": "text",
      "content": {"text": text}
    }),
  )
      .catchError((e) {
    loggerError('企业微信发送失败:${e.message}');
    throw e;
  });

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
  bool? isShorebird,
}) async {
  loggerDebug('下载缓存到本地中，请稍等......');
  final args = <String>[
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
  ];
  if (isShorebird != null) {
    args.addAll(['--isShorebird', isShorebird.toString()]);
  }
  await ProcessRunner().runProcess(
    args,
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
  loggerDebug('writeEnvironmentValueInFile:$filePath $key=$value');
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
    if (!contents.contains(environmentContent)) {
      contents.add(environmentContent);
    }
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

/// 从目标目录下 local.properties 读取 hvigor.nodeOptions，返回 NODE_OPTIONS 环境变量覆盖。
/// 未配置时返回 null（ProcessRunner 会继承父环境，不影响内存充足的机器）。
Map<String, String>? envOverrideFromLocalProperties(Directory dir) {
  final propsFile = File(join(dir.path, 'local.properties'));
  if (!propsFile.existsSync()) {
    return null;
  }
  String? nodeOptions;
  for (final line in propsFile.readAsLinesSync()) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) {
      continue;
    }
    final eq = trimmed.indexOf('=');
    if (eq <= 0) {
      continue;
    }
    final key = trimmed.substring(0, eq).trim();
    final value = trimmed.substring(eq + 1).trim();
    if (key == 'hvigor.nodeOptions') {
      nodeOptions = value;
    }
  }
  if (nodeOptions == null || nodeOptions.isEmpty) {
    return null;
  }
  return {'NODE_OPTIONS': nodeOptions};
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

/// 读取 Android / OHOS `local.properties`（支持 `sdk.dir` 等带点 key）。
Map<String, String> readLocalPropertiesFile(File file) {
  final map = <String, String>{};
  if (!file.existsSync()) return map;
  for (final raw in file.readAsLinesSync()) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#') || line.startsWith('!')) {
      continue;
    }
    final eq = line.indexOf('=');
    if (eq <= 0) continue;
    final key = line.substring(0, eq).trim();
    var value = line.substring(eq + 1).trim();
    value = value.replaceAll(r'\:', ':').replaceAll(r'\=', '=');
    if (key.isNotEmpty) map[key] = value;
  }
  return map;
}

class AndroidNdkValidation {
  final bool ok;
  final String detail;
  final String fix;

  const AndroidNdkValidation({
    required this.ok,
    required this.detail,
    required this.fix,
  });
}

/// 校验 `ndk.dir` 是否指向可用的 NDK 根目录。
AndroidNdkValidation validateAndroidNdkDir(String ndkDir) {
  final trimmed = ndkDir.trim();
  if (trimmed.isEmpty) {
    return const AndroidNdkValidation(
      ok: false,
      detail: '未配置 ndk.dir',
      fix: '配置 NDK_DIR 后执行 metax init app_environment / project',
    );
  }
  final dir = Directory(trimmed);
  if (!dir.existsSync()) {
    return AndroidNdkValidation(
      ok: false,
      detail: 'NDK 目录不存在: $trimmed',
      fix: '用 sdkmanager 安装对应 NDK，或把 ndk.dir 改成本机已有版本'
          '（如 ~/Library/Android/sdk/ndk/<version>）',
    );
  }
  final ndkBuild = File(join(trimmed, 'ndk-build'));
  final sourceProps = File(join(trimmed, 'source.properties'));
  final hasMarker = ndkBuild.existsSync() || sourceProps.existsSync();
  if (!hasMarker) {
    return AndroidNdkValidation(
      ok: false,
      detail: '目录存在但不是完整 NDK（缺少 ndk-build / source.properties）: $trimmed',
      fix: '重新安装该 NDK 版本，或改 ndk.dir 指向完整安装目录',
    );
  }
  return AndroidNdkValidation(
    ok: true,
    detail: trimmed,
    fix: '',
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
  final environment = readLocalPropertiesFile(localPropertyFile);
  final ndkDir = environment['ndk.dir'];
  if (ndkDir == null || ndkDir.trim().isEmpty) {
    throw '请先通过 metax init app_environment 初始化安卓环境 ndk.dir 变量';
  }
  final status = validateAndroidNdkDir(ndkDir);
  if (!status.ok) {
    throw '${status.detail}\n${status.fix}';
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

/// 透传缓存相关全局参数给子进程 metax 调用
List<String> getUseCacheCommands({
  bool? flutterCache,
  bool? unityCache,
}) {
  return [
    isUseCache ? '--isUseCache' : '--no-isUseCache',
    (flutterCache ?? isUseFlutterCache)
        ? '--isUseFlutterCache'
        : '--no-isUseFlutterCache',
    (unityCache ?? isUseUnityCache)
        ? '--isUseUnityCache'
        : '--no-isUseUnityCache',
  ];
}

/// 获取 Flutter SDK 根目录（优先工程 FVM：fvm flutter 自动向上找 .fvmrc）
Future<String> getFlutterCommandDir(AppHomeDir appHomeDir) async {
  final projectDir = appHomeDir.flutterDir;
  try {
    final sdk = await resolveFlutterSdk(projectDir);
    if (sdk.flutterRoot.isNotEmpty) {
      return sdk.flutterRoot;
    }
  } catch (e) {
    loggerWarning('resolveFlutterSdk 失败，回退 which flutter: $e');
  }
  final flutterBinPath = await ProcessRunner().runProcess(
    ['which', 'flutter'],
    printOutput: true,
  ).then((e) => pickFlutterBinPath(e.output) ?? e.output.split('\n').first.trim());
  if (!flutterBinPath.contains(Platform.pathSeparator)) {
    throw Exception('无法从 which flutter 解析绝对路径: $flutterBinPath');
  }
  return File(flutterBinPath).parent.parent.path;
}

/// 初始化Flutter环境
Future<void> initFlutterEnvironment({
  required AppHomeDir appHomeDir,
  required String buildType,
  required String configuration,
  required bool isStore,
  required String androidChannel,
  required Map branchConfig,
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
      '--branchConfig',
      jsonEncode(branchConfig),
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

Future<List<FlutterWebVersionData>> getFlutterModuleVersions({
  required String workspace,
  required List<GitSubmodule> gitSubmodules,
}) async {
  final flutterModuleVersions = <FlutterWebVersionData>[];
  for (var submodule in gitSubmodules) {
    final name = submodule.name;
    final path = submodule.path;
    final branch = submodule.branch;
    if (name == null || path == null || branch == null) {
      continue;
    }
    final submoduleDir = join(workspace, path);
    final submoduleRepo = join(submoduleDir, '.git');
    if (await Directory(submoduleRepo).exists()) {
      continue;
    }
    final flutterWebVersionFile = join(submoduleDir, '.flutter_web_version');
    int flutterWebVersion = 0;
    if (await File(flutterWebVersionFile).exists()) {
      final flutterWebVersionContent =
          await File(flutterWebVersionFile).readAsString();
      flutterWebVersion = int.parse(flutterWebVersionContent);
    }

    /// 获取当前 git 最新提交的时间 输出 13 位时间戳
    final gitLog = await ProcessRunner().runProcess(
      [
        'git',
        'log',
        '--format=%ct',
        '-1',
      ],
      workingDirectory: Directory(submoduleDir),
      printOutput: false,
    );
    final gitLogTime = gitLog.stdout.toString().trim();
    flutterModuleVersions.add(FlutterWebVersionData(
      name: name,
      branch: branch,
      version: flutterWebVersion,
      gitVersion: int.parse(gitLogTime) * 1000,
    ));
  }
  return flutterModuleVersions;
}

/// 生成依赖的特殊分支字符串
String generateSpecialBranchString(List<GitSubmodule> gitSubmodules) {
  final specialBranchString = <String>[];
  for (var module in gitSubmodules) {
    final branch = module.branch;
    specialBranchString.add('${module.name}:$branch');
  }
  return specialBranchString.join(',');
}

/// 生成依赖的热更版本字符串
String generateSpecialVersionStringForFlutterWeb(
    List<FlutterWebVersionData> flutterWebVersionDatas) {
  final specialVersionString = <String>[];
  for (var module in flutterWebVersionDatas) {
    final version = module.version;
    specialVersionString.add('${module.name}:$version');
  }
  return specialVersionString.join(',');
}
