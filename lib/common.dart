import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:color_logger/color_logger.dart';
import 'package:dio/dio.dart';
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
  await ProcessRunner().runProcess(
    [
      'git',
      'reset',
      '--hard',
    ],
    workingDirectory: Directory(workingDirectory),
  );
  await ProcessRunner().runProcess(
    [
      'git',
      'fetch',
      'origin',
    ],
    workingDirectory: Directory(workingDirectory),
  );
  await ProcessRunner().runProcess(
    [
      'git',
      'switch',
      branch,
    ],
    workingDirectory: Directory(workingDirectory),
  );
  await ProcessRunner().runProcess([
    'git',
    'reset',
    '--hard',
    'origin/$branch',
  ], workingDirectory: Directory(workingDirectory));
  await ProcessRunner().runProcess([
    'git',
    'lfs',
    'pull',
    'origin',
    branch,
  ], workingDirectory: Directory(workingDirectory));
}

/// 获取当前的分支名称
Future<String> getCurrentBranch(String workingDirectory) async {
  final commands = ['git', 'rev-parse', '--abbrev-ref', 'HEAD'];
  return ProcessRunner(defaultWorkingDirectory: Directory(workingDirectory))
      .runProcess(commands, printOutput: true)
      .then((result) => result.stdout.trim());
}

/// 获取当前的commit hash
Future<String> getCurrentCommitHash(String workingDirectory) async {
  final commands = ['git', 'rev-parse', 'HEAD'];
  return ProcessRunner(defaultWorkingDirectory: Directory(workingDirectory))
      .runProcess(commands, printOutput: true)
      .then((result) => result.stdout.trim());
}

String readEnv(String envName) {
  if (!Platform.environment.keys.contains(envName)) {
    throw "请设置环境变量 【$envName】";
  }
  return Platform.environment[envName]!;
}

void checkEnv(String envName) {
  if (!Platform.environment.keys.contains(envName)) {
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
    throw 'Unity工程的build_version.txt文件不存在';
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
  await ProcessRunner().runProcess([
    'unzip',
    zipPath,
    '-d',
    targetDir.path,
  ]);
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
  required bool isStore,
  required String branch,
  required String commitHash,
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
      '--isStore',
      isStore.toString(),
      '--branch',
      branch,
      '--commitHash',
      commitHash,
    ],
    printOutput: true,
  );
}

/// 使用缓存
Future<void> useCache({
  required String workspace,
  required BuildPlatform buildPlatform,
  required BuildLibrary buildLibrary,
  required BuildConfiguration buildConfiguration,
  required BuildType buildType,
  required bool isStore,
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
      '--isStore',
      isStore.toString(),
      '--commitHash',
      commitHash,
      '--buildId',
      buildId.toString(),
    ],
    printOutput: true,
  );
}
