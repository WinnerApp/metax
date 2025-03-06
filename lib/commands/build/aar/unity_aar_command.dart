import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:meta_tool/common.dart';
import 'package:meta_tool/define.dart';
import 'package:path/path.dart';
import 'package:process_runner/process_runner.dart';

class UnityAarCommand extends Command {
  @override
  String get description => '打包unity aar';

  @override
  String get name => 'unity';

  UnityAarCommand() {
    argParser.addOption('workspace', abbr: 's', help: '安卓目录');
  }

  @override
  Future<void> run() async {
    final workspace = argResults?['workspace'] ?? Directory.current.path;
    final unityDir = Directory(join(workspace, 'unityLibrary'));
    if (!unityDir.existsSync()) {
      throw Exception('unityLibrary目录不存在: ${unityDir.path}');
    }
    final localBundleDir = Directory(join(
      unityDir.path,
      'src',
      'main',
      'assets',
      'LocalBundles',
    ));

    /// cp -rf "$local_bundle_path" "$android_dir/app/src/main/assets"
    await ProcessRunner().runProcess(
      [
        'cp',
        '-rf',
        localBundleDir.path,
        "${workspace.path}/app/src/main/assets"
      ],
      workingDirectory: workspace,
      printOutput: true,
    );

    /// rm -rf "$local_bundle_path"
    await ProcessRunner().runProcess(
      ['rm', '-rf', localBundleDir.path],
      workingDirectory: workspace,
      printOutput: true,
    );

    /// ./gradlew unityLibrary:bundleReleaseAar
    await ProcessRunner().runProcess(
      ['./gradlew', 'unityLibrary:bundleReleaseAar'],
      workingDirectory: workspace,
      printOutput: true,
    );
    loggerSuccess('打包成功!');
  }
}
