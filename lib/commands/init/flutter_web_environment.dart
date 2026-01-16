import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:meta_tool/app_home_dir.dart';
import 'package:meta_tool/common.dart';
import 'package:meta_tool/flutter_web_version_data.dart';
import 'package:meta_tool/git_submodule_parse.dart';
import 'package:path/path.dart';

class FlutterWebEnvironmentCommand extends Command {
  @override
  String get description => '初始化 Flutter Web 环境';

  @override
  String get name => 'flutter_web_environment';

  @override
  FutureOr? run() async {
    await _initFlutterHotUpdateConfigFile(workspace: Directory.current.path);
  }

  /// 初始化 Flutter 热更配置文件
  Future<void> _initFlutterHotUpdateConfigFile({
    required String workspace,
  }) async {
    final gitModuleFile = await getGitmodulesFilePath(workspace);
    if (!await File(gitModuleFile).exists()) {
      throw Exception('$gitModuleFile not exists');
    }
    final gitSubmodules = await parseGitmodulesFile(gitModuleFile);
    final pages = Directory(join(workspace, 'packages', 'flutter_metax_pages'))
        .listSync()
        .whereType<Directory>()
        .map((e) => basename(e.path))
        .toList();
    List<FlutterWebVersionData> moduleVersions = await getFlutterModuleVersions(
      workspace: workspace,
      gitSubmodules: gitSubmodules,
    );
    final branchText = generateSpecialBranchString(gitSubmodules);
    final versionText =
        generateSpecialVersionStringForFlutterWeb(moduleVersions);
    Map<String, dynamic> branchConfig = {};
    for (var moduleVersion in moduleVersions) {
      final name = moduleVersion.name;
      branchConfig[name] = moduleVersion.toJson();
      if (name == 'packages/flutter_metax_pages') {
        for (var page in pages) {
          branchConfig[page] = {
            'branch': moduleVersion.branch,
            'git_version': moduleVersion.gitVersion,
            'name': page,
            'version': moduleVersion.version,
          };
        }
      }
    }
    branchConfig['package_branch_text'] = branchText;
    branchConfig['package_version_text'] = versionText;
    final dartDefineFile = File(join(
      AppHomeDir(workspace).flutterDir.path,
      'assets',
      'dart_define.json',
    ));
    if (!await dartDefineFile.exists()) {
      throw Exception('${dartDefineFile.path} not exists');
    }
    final dartDefineContent = await dartDefineFile.readAsString();
    final dartDefineJson = jsonDecode(dartDefineContent);
    dartDefineJson['branchConfig'] = branchConfig;
    final newDartDefineContent = jsonEncode(dartDefineJson);
    await dartDefineFile.writeAsString(newDartDefineContent);
  }
}
