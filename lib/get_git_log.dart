import 'dart:io';

import 'package:meta_tool/common.dart';
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
    loggerDebug('获取git日志[$root]: $beforeCommitId..$afterCommitId');
    if (beforeCommitId == afterCommitId) {
      /// 代表没有更新 则返回空的日志
      return null;
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
      if (message.startsWith("CR-link:")) continue;
      if (message.startsWith("Signed-off-by:")) continue;
      if (message.startsWith("Reviewed-by:")) continue;
      if (message.isNotEmpty) {
        messages.add(message);
      }
    }
    if (messages.isEmpty) {
      return null;
    }
    return messages.join('\n');
  }
}
