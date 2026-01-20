import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:meta_tool/common.dart';
import 'package:meta_tool/git_submodule_parse.dart';
import 'package:path/path.dart';
import 'package:prompts/prompts.dart' as prompts;

class FlutterWebVersionCommand extends Command {
  @override
  String get name => 'flutter_web_version';

  @override
  String get description => '初始化flutter web版本';

  @override
  Future<void> run() async {
    final gitSubmodulePath = await getGitmodulesFilePath(Directory.current.path);
    loggerDebug('gitSubmodulePath: $gitSubmodulePath');
    if (!File(gitSubmodulePath).existsSync()) {
      throw Exception('当前目录不是棉宇宙主目录');
    }
    final gitSubmodules = await parseGitmodulesFile(gitSubmodulePath);
    final submoduleName = prompts.choose(
      '请选择需要升级的子模块',
      gitSubmodules.map((e) => e.name).toList(),
    );
    if (submoduleName == null) {
      throw Exception('未选择子模块');
    }
    final submodule = gitSubmodules.firstWhere((e) => e.name == submoduleName);
    int version = 1;
    final versionFile = File(
        join(Directory.current.path, submodule.path, '.flutter_web_version'));
    if (versionFile.existsSync()) {
      version = int.parse(versionFile.readAsStringSync());
      version++;
    }
    if (!versionFile.existsSync()) {
      versionFile.createSync(recursive: true);
    }
    versionFile.writeAsStringSync(version.toString());
    loggerSuccess('升级成功，版本号：$version');
  }
}
