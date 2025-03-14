import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:meta_tool/app_home_dir.dart';
import 'package:meta_tool/appwrite_environment.dart';
import 'package:meta_tool/argument_get.dart';
import 'package:meta_tool/commands/unity_environment.dart';
import 'package:meta_tool/common.dart';
import 'package:meta_tool/define.dart';
import 'package:path/path.dart';

class InitCacheCommand extends Command {
  @override
  String get description => '初始化缓存';

  @override
  String get name => 'cache';

  InitCacheCommand() {
    argParser.addOption(
      'workspace',
      help: '工作空间路径',
      defaultsTo: Directory.current.path,
    );
    argParser.addOption(
      'branch',
      help: '分支',
    );
    argParser.addOption(
      'unityBranch',
      help: 'unity分支',
    );
    argParser.addOption(
      'configuration',
      help: '请输入配置',
      allowed: BuildConfiguration.values.map((e) => e.name).toList(),
    );
    argParser.addOption(
      'isStore',
      help: '是否属于市场资源',
      allowed: ['true', 'false'],
    );
  }

  @override
  FutureOr? run() async {
    final workspace = argResults?['workspace'];
    final appHomeDir = AppHomeDir(workspace: workspace);
    final appwriteEnvironment = AppwriteCacheEnvironment();
    final unityEnvironment = UnityEnvironment();

    final flutterBranchs =
        await getLatestBranchList(appHomeDir.flutterDir.path);
    final branch = ArgumentGet(argResults).getString(
      'branch',
      allowed: flutterBranchs,
    );
    final flutterSwitchBranch = getBranchName(branch);
    await switchBranch(appHomeDir.flutterDir.path, flutterSwitchBranch);
    final unityWorkspace = join(
      unityEnvironment.unityWorkspace,
      unityEnvironment.iosUnityPath,
    );
    final unityBranchs = await getLatestBranchList(unityWorkspace);
    final unityBranch = ArgumentGet(argResults).getString(
      'unityBranch',
      allowed: unityBranchs,
    );
    final unitySwitchBranch = getBranchName(unityBranch);
    await switchBranch(unityWorkspace, unitySwitchBranch);
    final configuration = ArgumentGet(argResults).getString(
      'configuration',
      allowed: BuildConfiguration.values.map((e) => e.name).toList(),
    );
    final isStore = ArgumentGet(argResults)
            .getString('isStore', allowed: ['true', 'false']) ==
        'true';
  }
}
