import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:meta_tool/common.dart';
import 'package:path/path.dart';
import 'package:prompts/prompts.dart' as prompts;

class BranchCommand extends Command {
  @override
  String get description => '初始化分支';

  @override
  String get name => 'branch';

  BranchCommand() {
    argParser.addOption(
      'workspace',
      help: '工作目录',
      defaultsTo: Directory.current.path,
    );
  }

  @override
  FutureOr? run() async {
    final workspace = argResults?['workspace'];
    final iosDir = Directory(join(workspace, 'ios'));
    final androidDir = Directory(join(workspace, 'android'));
    final flutterDir = Directory(join(workspace, 'metaapp_flutter'));
    if (iosDir.existsSync()) {
      await _initBranch(iosDir, '请选择IOS分支');
    }
    if (androidDir.existsSync()) {
      await _initBranch(androidDir, '请选择Android分支');
    }
    if (flutterDir.existsSync()) {
      await _initBranch(flutterDir, '请选择Flutter分支');
    }
  }

  Future<void> _initBranch(Directory dir, String message) async {
    if (!await isGitRepository(dir.path)) {
      throw '[$dir]不是git仓库';
    }
    final branchs = await getLatestBranchList(dir.path);
    final branch = prompts.choose(
      message,
      branchs,
    );
    if (branch == null) {
      throw '请选择要切换的分支';
    }
    await switchBranch(dir.path, branch);
  }
}
