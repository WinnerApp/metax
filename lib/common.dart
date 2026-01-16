import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:color_logger/color_logger.dart';
import 'package:dio/dio.dart';
import 'package:meta_tool/app_home_dir.dart';
import 'package:meta_tool/define.dart';
import 'package:meta_tool/flutter_web_version_data.dart';
import 'package:meta_tool/git_submodule_parse.dart';
import 'package:path/path.dart';
import 'package:process_runner/process_runner.dart';

/// 运行进程并检查退出码，失败时抛出异常
/// 这是所有命令执行的标准方法，确保异常能被正确捕获并导致程序退出
Future<ProcessRunnerResult> runProcessChecked(
  List<String> command, {
  Directory? workingDirectory,
  Map<String, String>? environment,
  bool printOutput = true,
}) async {
  final result = await ProcessRunner(
    environment: environment,
    defaultWorkingDirectory: workingDirectory,
  ).runProcess(
    command,
    printOutput: printOutput,
  );

  if (result.exitCode != 0) {
    final commandStr = command.join(' ');
    final errorMsg = result.stderr.toString().trim();
    final outputMsg = result.stdout.toString().trim();
    throw Exception(
      '命令执行失败: $commandStr\n'
      '退出码: ${result.exitCode}\n'
      '${errorMsg.isNotEmpty ? "错误输出:\n$errorMsg\n" : ""}'
      '${outputMsg.isNotEmpty ? "标准输出:\n$outputMsg" : ""}',
    );
  }

  return result;
}

/// 在 PATH 中查找可执行文件（跨平台）
/// - Windows 会额外尝试：.exe/.cmd/.bat
Future<String?> findExecutableOnPath(String name,
    {Map<String, String>? environment}) async {
  final env = {...Platform.environment, ...?environment};
  final pathVar = env['PATH'];
  if (pathVar == null || pathVar.trim().isEmpty) {
    return null;
  }
  final sep = Platform.isWindows ? ';' : ':';
  final parts =
      pathVar.split(sep).map((e) => e.trim()).where((e) => e.isNotEmpty);
  final candidates = <String>[name];
  if (Platform.isWindows) {
    // 常见可执行后缀
    if (!name.toLowerCase().endsWith('.exe')) candidates.add('$name.exe');
    if (!name.toLowerCase().endsWith('.cmd')) candidates.add('$name.cmd');
    if (!name.toLowerCase().endsWith('.bat')) candidates.add('$name.bat');
  }
  for (final dir in parts) {
    for (final c in candidates) {
      final file = File(join(dir, c));
      if (file.existsSync()) {
        return file.path;
      }
    }
  }
  return null;
}

/// 命令是否可用（跨平台）
Future<bool> isCommandAvailable(String name,
    {Map<String, String>? environment}) async {
  // 优先走系统自带的 where/which，避免 PATH 里同名非可执行文件误判
  try {
    final runner = ProcessRunner(environment: environment);
    final result = await runner.runProcess(
      Platform.isWindows ? ['where', name] : ['which', name],
      printOutput: false,
    );
    final out = result.stdout.toString().trim();
    if (out.isNotEmpty) return true;
  } catch (_) {
    // ignore
  }
  return (await findExecutableOnPath(name, environment: environment)) != null;
}

/// 递归复制目录（纯 Dart，跨平台）
Future<void> copyDirectoryRecursive(
  Directory sourceDir,
  Directory targetDir, {
  bool deleteTargetIfExists = true,
}) async {
  if (!await sourceDir.exists()) {
    throw '源目录不存在: ${sourceDir.path}';
  }
  if (await targetDir.exists()) {
    if (deleteTargetIfExists) {
      await targetDir.delete(recursive: true);
    } else {
      throw '目标目录已存在: ${targetDir.path}';
    }
  }
  await targetDir.create(recursive: true);
  await for (final entity
      in sourceDir.list(recursive: false, followLinks: false)) {
    final name = basename(entity.path);
    final newPath = join(targetDir.path, name);
    if (entity is File) {
      await entity.copy(newPath);
    } else if (entity is Directory) {
      await copyDirectoryRecursive(entity, Directory(newPath),
          deleteTargetIfExists: false);
    } else if (entity is Link) {
      // Windows/权限环境下 Link 可能失败：尽量解析为真实文件/目录再复制
      try {
        final resolved = await entity.resolveSymbolicLinks();
        final resolvedType = FileSystemEntity.typeSync(resolved);
        if (resolvedType == FileSystemEntityType.file) {
          await File(resolved).copy(newPath);
        } else if (resolvedType == FileSystemEntityType.directory) {
          await copyDirectoryRecursive(
            Directory(resolved),
            Directory(newPath),
            deleteTargetIfExists: false,
          );
        }
      } catch (_) {
        // ignore link copy
      }
    }
  }
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
  return isCommandAvailable(name);
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

/// 压缩目录到zip文件（跨平台）
Future<void> compressDirToZip(String zipPath, Directory sourceDir) async {
  // Windows 上默认没有 zip：优先用 PowerShell Compress-Archive
  if (Platform.isWindows) {
    // PowerShell 的 Compress-Archive 需要绝对路径，并且使用 * 来包含所有内容
    // 路径需要正确转义，使用双引号并转义内部的双引号和反斜杠
    final sourcePath =
        sourceDir.path.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
    final zipPathEscaped =
        zipPath.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
    // 使用 Dart 字符串插值将路径值插入到 PowerShell 命令中
    final command =
        'Compress-Archive -Path "$sourcePath\\*" -DestinationPath "$zipPathEscaped" -Force';
    await ProcessRunner().runProcess(
      [
        'powershell',
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        command,
      ],
      printOutput: true,
    );
  } else {
    // Unix/Linux/macOS 使用 zip 命令
    await ProcessRunner().runProcess(
      [
        'zip',
        '-r',
        zipPath,
        './',
      ],
      workingDirectory: sourceDir,
      printOutput: true,
    );
  }
}

/// 复制zip 到指定目录下面并先清空当前目录
Future<void> copyZipToDir(String zipPath, Directory targetDir) async {
  if (await targetDir.exists()) {
    await targetDir.delete(recursive: true);
  }
  await targetDir.create(recursive: true);
  // Windows 上默认没有 unzip：优先用 PowerShell Expand-Archive
  if (Platform.isWindows) {
    await ProcessRunner().runProcess(
      [
        'powershell',
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        'Expand-Archive -Path "$zipPath" -DestinationPath "${targetDir.path}" -Force',
      ],
      printOutput: true,
    );
    return;
  }
  await ProcessRunner().runProcess(
    ['unzip', '-o', zipPath, '-d', targetDir.path],
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
  await runProcessChecked(
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
  await runProcessChecked(
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
  await runProcessChecked(
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
    // 去除首尾空白
    line = line.trim();
    // 跳过空行和注释行
    if (line.isEmpty || line.startsWith('#')) {
      continue;
    }
    // 处理 export KEY=VALUE 格式
    if (line.startsWith('export ')) {
      line = line.substring(7).trim();
    }
    // 查找等号位置
    final equalIndex = line.indexOf('=');
    if (equalIndex == -1) {
      continue;
    }
    final key = line.substring(0, equalIndex).trim();
    var value = line.substring(equalIndex + 1).trim();

    // 处理引号包裹的值
    if ((value.startsWith('"') && value.endsWith('"')) ||
        (value.startsWith("'") && value.endsWith("'"))) {
      value = value.substring(1, value.length - 1);
    }

    if (key.isNotEmpty) {
      environment[key] = value;
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
  final candidates = Platform.isWindows
      ? [
          File(join(ndkDir, 'ndk-build.cmd')),
          File(join(ndkDir, 'ndk-build.bat')),
          File(join(ndkDir, 'ndk-build')),
        ]
      : [File(join(ndkDir, 'ndk-build'))];
  if (!candidates.any((f) => f.existsSync())) {
    throw 'ndk.dir路径错误，请检查是否正确！';
  }
}

/// 复制目录到指定目录
Future<void> copyDirToDir(Directory sourceDir, Directory targetDir) async {
  await copyDirectoryRecursive(sourceDir, targetDir,
      deleteTargetIfExists: true);
}

String getUseMockCommand() {
  return useMock ? '--isUseMock' : '--no-isUseMock';
}

/// 获取Flutter命令路径
Future<String> getFlutterCommandDir(AppHomeDir appHomeDir) async {
  final flutterPath = await findExecutableOnPath('flutter') ??
      await findExecutableOnPath('flutter.bat');
  if (flutterPath == null) {
    throw '找不到 flutter 可执行文件，请确认已安装并加入 PATH';
  }
  // flutter 可执行在 <flutter>/bin/flutter(.bat/.exe)
  return File(flutterPath).parent.parent.path;
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
  await runProcessChecked(
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
  await runProcessChecked(
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
