import 'dart:io';

import 'package:process_runner/process_runner.dart';

class GetGitLog {
  final String root;
  final String beforeCommitId;
  final String afterCommitId;

  GetGitLog({
    required this.root,
    required this.beforeCommitId,
    required this.afterCommitId,
  });

  Future<String?> get() async {
    late String result;
    result = await ProcessRunner().runProcess(
      ['git', 'log', '$beforeCommitId^..$afterCommitId'],
      workingDirectory: Directory(root),
    ).then((value) => value.output);
    final messages = <String>[];
    for (var element in result.split('\n')) {
      /// 删除日志左右的空格
      final message = element.trim();
      if (message.isEmpty) continue;
      if (message.isNotEmpty) {
        messages.add(message);
      }
    }
    final logContent = messages.join('\n');
    return logContent;
  }
}
