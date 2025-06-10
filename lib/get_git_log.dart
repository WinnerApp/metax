import 'dart:io';

import 'package:process_runner/process_runner.dart';

class GetGitLog {
  final String root;
  final String? beforeCommitId;
  final String afterCommitId;

  GetGitLog({
    required this.root,
    required this.beforeCommitId,
    required this.afterCommitId,
  });

  Future<String?> get() async {
    if (beforeCommitId == afterCommitId) {
      /// 代表没有更新 则返回空的日志
      return '';
    }

    /// 如果没有设置beforeCommitId 则设置和afterCommitId相同的beforeCommitId
    final startCommitId = beforeCommitId ?? afterCommitId;
    late String result;
    result = await ProcessRunner().runProcess(
      ['git', 'log', '$startCommitId^..$afterCommitId'],
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
