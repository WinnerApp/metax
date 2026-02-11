import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:meta_tool/argument_get.dart';
import 'package:meta_tool/common.dart';
import 'package:meta_tool/define.dart';
import 'package:meta_tool/unity_environment.dart';
import 'package:process_runner/process_runner.dart';

class ExportFirstPackageCommand extends Command {
  @override
  String get description => '导出第Unity首包';

  @override
  String get name => 'export_first_package';

  ExportFirstPackageCommand() {
    argParser.addOption('platform', help: '平台', allowed: ['ios', 'android']);
    argParser.addOption('unityBranch', help: 'Unity分支');
    argParser.addFlag('skipBuild', help: '是否跳过构建');
  }

  @override
  FutureOr? run() async {
    final skipBuild = argResults?['skipBuild'] ?? false;
    final platform = ArgumentGet(argResults).getString(
      'platform',
      '请选择平台',
      allowed: ['ios', 'android'],
    );
    final unityEnvironment = UnityEnvironment.fromEnvironment(appHomeDir);
    final unityProjectDir = Directory(
      switch (platform) {
        'ios' => unityEnvironment.iosUnityWorkspace,
        'android' => unityEnvironment.androidUnityWorkspace,
        String() => throw UnimplementedError(),
      },
    );
    if (!unityProjectDir.existsSync()) {
      throw 'Unity项目目录不存在: ${unityProjectDir.path}';
    }

    final unityBranchs = await getLatestBranchList(unityProjectDir.path).then(
      (e) => e.map((e) => getBranchName(e)).toList(),
    );

    final unityBranch = ArgumentGet(argResults).getString(
      'unityBranch',
      '请选择Unity分支',
      allowed: unityBranchs,
    );

    /// 切换分支
    await switchBranch(unityProjectDir.path, unityBranch);
    final env = loadAppEnvironment(appHomeDir);
    final unityEnginePath = env['UNITY_ENGINE_PATH'];
    if (unityEnginePath == null) {
      throw '找不到 Unity 引擎路径';
    }

    bool isSuccess = false;
    // final streamController = StreamController<List<int>>.broadcast();
    // streamController.stream.listen((event) {
    //   String data = String.fromCharCodes(event);
    //   loggerDebug(data);
    //   if (data.contains('Exiting batchmode successfully now!')) {
    //     isSuccess = true;
    //   }
    // });

    if (!skipBuild) {
      final result = await ProcessRunner().runProcess(
        [
          unityEnginePath,
          '-quit',
          '-batchmode',
          '-executeMethod',
          'ExportAppData.exportFirstPackage',
          '-nographics',
          '-projectPath',
          './'
        ],
        printOutput: true,
        workingDirectory: unityProjectDir,
        // stdin: streamController.stream,
      );
      loggerSuccess('导出Unity首包成功');
    }
    // Assets\StreamingAssets\InnerAssets
    // final path = join('Assets', 'StreamingAssets', 'InnerAssets');
    // final gitAddResult = await ProcessRunner().runProcess(
    //   ['git', 'add', path],
    //   printOutput: true,
    //   workingDirectory: unityProjectDir,
    // );
    // if (gitAddResult.stderr.isNotEmpty) {
    //   throw 'git add $path失败: ${gitAddResult.stderr}';
    // }
    // final gitCommitResult = await ProcessRunner().runProcess(
    //   ['git', 'commit', '-m', 'export first package'],
    //   printOutput: true,
    //   workingDirectory: unityProjectDir,
    // );
    // if (gitCommitResult.stderr.isNotEmpty) {
    //   throw 'git commit -m export first package失败: ${gitCommitResult.stderr}';
    // }
    // final gitPushResult = await ProcessRunner().runProcess(
    //   ['git', 'push', 'origin', unityBranch],
    //   printOutput: true,
    //   workingDirectory: unityProjectDir,
    // );
    // if (gitPushResult.stderr.isNotEmpty) {
    //   throw 'git push origin $unityBranch失败: ${gitPushResult.stderr}';
    // }
    return super.run();
  }
}
