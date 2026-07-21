import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:meta_tool/argument_get.dart';
import 'package:meta_tool/common.dart';
import 'package:meta_tool/define.dart';
import 'package:meta_tool/unity_environment.dart';
import 'package:path/path.dart';
import 'package:process_runner/process_runner.dart';

class ExportFirstPackageCommand extends Command {
  @override
  String get description => '导出第Unity首包';

  @override
  String get name => 'export_first_package';

  ExportFirstPackageCommand() {
    argParser.addOption('platform', help: '平台', allowed: ['ios', 'android', 'ohos']);
    argParser.addOption('unityBranch', help: 'Unity分支');
    argParser.addFlag('skipBuild', help: '是否跳过构建');

    /// 是否支持上传 默认不支持
    argParser.addFlag('uploadGit', help: '是否支持上传 git');
  }

  @override
  FutureOr? run() async {
    final skipBuild = argResults?['skipBuild'] ?? false;
    final platform = ArgumentGet(argResults).getString(
      'platform',
      '请选择平台',
      allowed: ['ios', 'android', 'ohos'],
    );
    final unityEnvironment = UnityEnvironment.fromEnvironment(appHomeDir);
    final unityProjectDir = Directory(
      switch (platform) {
        'ios' => unityEnvironment.iosUnityWorkspace,
        'android' => unityEnvironment.androidUnityWorkspace,
        'ohos' => unityEnvironment.ohosUnityWorkspace,
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
    final unityEnginePath = switch (platform) {
      'ohos' => env['TUANJIE_ENGINE_PATH'],
      _ => env['UNITY_ENGINE_PATH'],
    };
    if (unityEnginePath == null) {
      throw platform == 'ohos' ? '找不到团结引擎路径' : '找不到 Unity 引擎路径';
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
      final stdout = result.stdout;
      bool isSuccess = stdout.contains('Exiting batchmode successfully now!');
      if (!isSuccess) {
        throw 'Unity 打包失败';
      }
      loggerSuccess('导出Unity首包成功');
    }
    // Assets\StreamingAssets\InnerAssets
    bool isUploadGit = argResults?['uploadGit'] ?? false;
    if (isUploadGit) {
      final path = join(
        'Assets',
        'StreamingAssets',
        'InnerAssets',
      );

      final gitStatusResult = await ProcessRunner().runProcess(
        ['git', 'status', path],
        workingDirectory: unityProjectDir,
      );
      final stdout = gitStatusResult.stdout;
      bool isClean = stdout.contains('nothing to commit, working tree clean');
      if (isClean) {
        throw '不存在本地缓存提交!';
      }

      final gitAddResult = await ProcessRunner().runProcess(
        ['git', 'add', path],
        printOutput: true,
        workingDirectory: unityProjectDir,
      );
      if (gitAddResult.stderr.isNotEmpty) {
        throw 'git add $path失败: ${gitAddResult.stderr}';
      }
      final gitCommitResult = await ProcessRunner().runProcess(
        ['git', 'commit', '-m', '"export first package"'],
        printOutput: true,
        workingDirectory: unityProjectDir,
      );
      if (gitCommitResult.stderr.isNotEmpty) {
        throw 'git commit -m export first package失败: ${gitCommitResult.stderr}';
      }
      final gitPushResult = await ProcessRunner().runProcess(
        ['git', 'push', 'origin', unityBranch],
        printOutput: true,
        workingDirectory: unityProjectDir,
      );
      if (gitPushResult.stderr.isNotEmpty) {
        throw 'git push origin $unityBranch失败: ${gitPushResult.stderr}';
      }
    }
  }
}
