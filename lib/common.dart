import 'dart:io';

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

Future<void> pullAndSwitchBranch(String workingDirectory, String branch,
    {bool resetToOrigin = false}) async {}

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
