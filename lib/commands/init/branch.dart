import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:meta_tool/common.dart';
import 'package:meta_tool/define.dart';
import 'package:meta_tool/flutter_sdk.dart';
import 'package:prompts/prompts.dart' as prompts;

class BranchCommand extends Command {
  @override
  String get description => '初始化分支';

  @override
  String get name => 'branch';

  @override
  FutureOr? run() async {
    if (appHomeDir.iosDir.existsSync()) {
      await _initBranch(appHomeDir.iosDir, '请选择IOS分支');
    }
    if (appHomeDir.androidDir.existsSync()) {
      await _initBranch(appHomeDir.androidDir, '请选择Android分支');
    }
    if (appHomeDir.flutterDir.existsSync()) {
      await _initBranch(appHomeDir.flutterDir, '请选择Flutter分支');
      // 切 Flutter 分支后按 .fvmrc 对齐 SDK（安装缺失版本 / 重建软链 / SDK 变化则清理）
      await ensureFlutterSdkReady(appHomeDir.flutterDir);
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
