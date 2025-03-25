import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:meta_tool/app_home_dir.dart';
import 'package:meta_tool/common.dart';
import 'package:prompts/prompts.dart' as prompts;

class BranchCommand extends Command {
  @override
  String get description => '初始化分支';

  @override
  String get name => 'branch';

  BranchCommand() {
    argParser.addOption(
      'workspace',
      help: 'App工作目录',
      defaultsTo: Directory.current.path,
    );
  }

  @override
  FutureOr? run() async {
    final workspace = argResults?['workspace'];
    final appHomeDir = AppHomeDir(workspace);
    if (appHomeDir.iosDir.existsSync()) {
      await _initBranch(appHomeDir.iosDir, '请选择IOS分支');
    }
    if (appHomeDir.androidDir.existsSync()) {
      await _initBranch(appHomeDir.androidDir, '请选择Android分支');
    }
    if (appHomeDir.flutterDir.existsSync()) {
      await _initBranch(appHomeDir.flutterDir, '请选择Flutter分支');
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
