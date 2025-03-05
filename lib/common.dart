import 'dart:io';

import 'package:process_runner/process_runner.dart';

/// 判断是否是git仓库
Future<bool> isGitRepository(String workingDirectory) async {
  final commands = ['git', 'rev-parse', '--is-inside-work-tree'];
  return ProcessRunner(defaultWorkingDirectory: Directory(workingDirectory))
      .runProcess(commands)
      .then((e) => e.output.trim() == 'true');
}

/// clone仓库
Future<void> cloneRepository(String workingDirectory, String url) async {
  final commands = ['git', 'clone', url, workingDirectory];
  await ProcessRunner().runProcess(commands);
}

Future<void> pullAndSwitchBranch(String workingDirectory, String branch,
    {bool resetToOrigin = false}) async {}

/// 获取当前的分支名称
Future<String> getCurrentBranch(String workingDirectory) async {
  final commands = ['git', 'rev-parse', '--abbrev-ref', 'HEAD'];
  return ProcessRunner(defaultWorkingDirectory: Directory(workingDirectory))
      .runProcess(commands)
      .then((result) => result.stdout.trim());
}
