import 'dart:io';
import 'package:meta_tool/common.dart';
import 'package:process_runner/process_runner.dart';

class GetGitLog {
  final String root;
  final String? beforeCommitId;

  GetGitLog({
    required this.root,
    this.beforeCommitId,
  });

  Future<String?> get() async {
    late String result;
    if (beforeCommitId == null) {
      result = await ProcessRunner().runProcess(
        ['git', 'log', '-1'],
        workingDirectory: Directory(root),
      ).then((value) => value.output);
    } else {
      final currentCommitId = await getCurrentCommitHash(root);
      result = await ProcessRunner().runProcess(
        ['git', 'log', '$beforeCommitId..$currentCommitId'],
        workingDirectory: Directory(root),
      ).then((value) => value.output);
    }
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
