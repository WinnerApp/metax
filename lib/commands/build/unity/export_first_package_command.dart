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
  }

  @override
  FutureOr? run() async {
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
    final streamController = StreamController<List<int>>.broadcast();
    streamController.stream.listen((event) {
      String data = String.fromCharCodes(event);
      loggerDebug(data);
      if (data.contains('Exiting batchmode successfully now!')) {
        isSuccess = true;
      }
    });

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
      stdin: streamController.stream,
    );
    if (!isSuccess) {
      throw '导出Unity首包失败: ${result.stdout}';
    } else {
      loggerSuccess('导出Unity首包成功');
    }
    return super.run();
  }
}
