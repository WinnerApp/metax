import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:meta_tool/common.dart';

class ProjectCommand extends Command {
  @override
  String get description => "初始化工程";

  @override
  String get name => "project";

  ProjectCommand() {
    argParser.addOption("path", abbr: "p", help: "工程路径，默认为当前路径");
    argParser.addOption("branch", abbr: "b", help: "分支名,默认为main");
    argParser.addOption('url', abbr: 'u', help: '仓库地址');
  }

  @override
  FutureOr? run() async {
    final workspace = argResults?["path"] ?? Directory.current.path;
    final branch = argResults?["branch"] ?? "main";
    final url = argResults?["url"];
    if (url == null) {
      throw '仓库地址不能为空';
    }
    final workspaceDir = Directory(workspace);
    if (!workspaceDir.existsSync()) {
      await cloneRepository(workspace, url);
    } else if (!await isGitRepository(workspace)) {
      throw '$workspace 已经存在并且不是一个git仓库';
    }
  }
}
