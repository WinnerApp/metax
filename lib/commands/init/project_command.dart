import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:meta_tool/common.dart';
import 'package:path/path.dart';
import 'package:prompts/prompts.dart' as prompts;

class ProjectCommand extends Command {
  @override
  String get description => "初始化工程";

  @override
  String get name => "project";

  ProjectCommand() {
    argParser.addOption(
      "workspace",
      help: "APP工作空间路径，默认为当前路径",
      defaultsTo: Directory.current.path,
    );
  }

  @override
  FutureOr? run() async {
    final workspace = argResults?["workspace"];
    final iosGitUrl = readEnv('IOS_GIT_URL');
    final androidGitUrl = readEnv('ANDROID_GIT_URL');
    final flutterGitUrl = readEnv('FLUTTER_GIT_URL');
    final iosProjectDir = Directory(join(workspace, 'ios'));
    final androidProjectDir = Directory(join(workspace, 'android'));
    final flutterProjectDir = Directory(join(workspace, 'metaapp_flutter'));
    if (!iosProjectDir.existsSync()) {
      await cloneRepository(iosProjectDir.path, iosGitUrl);
    }
    final iosBranchList = await getLatestBranchList(iosProjectDir.path);
    String? iosBranch = prompts.choose(
      '请选择IOS分支',
      iosBranchList,
    );
    if (iosBranch == null) {
      throw 'IOS分支不能为空';
    }
    await switchBranch(iosProjectDir.path, iosBranch);
    if (!androidProjectDir.existsSync()) {
      await cloneRepository(androidProjectDir.path, androidGitUrl);
    }
    final androidBranchList = await getLatestBranchList(androidProjectDir.path);
    String? androidBranch = prompts.choose(
      '请选择Android分支',
      androidBranchList,
    );
    if (androidBranch == null) {
      throw 'Android分支不能为空';
    }
    await switchBranch(androidProjectDir.path, androidBranch);
    if (!flutterProjectDir.existsSync()) {
      await cloneRepository(flutterProjectDir.path, flutterGitUrl);
    }
    final flutterBranchList = await getLatestBranchList(flutterProjectDir.path);
    String? flutterBranch = prompts.choose(
      '请选择Flutter分支',
      flutterBranchList,
    );
    if (flutterBranch == null) {
      throw 'Flutter分支不能为空';
    }
    await switchBranch(flutterProjectDir.path, flutterBranch);
  }
}
