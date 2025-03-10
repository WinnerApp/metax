import 'dart:io';
import 'package:meta_tool/define.dart';
import 'package:path/path.dart';
import 'package:process_runner/process_runner.dart';
import 'package:color_logger/color_logger.dart';

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
Future<void> copyFile(File source, File target) async {
  if (target.existsSync()) {
    throw '文件已存在: ${target.path}';
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
