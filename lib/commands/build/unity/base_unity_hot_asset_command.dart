import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:meta_tool/app_home_dir.dart';
import 'package:meta_tool/common.dart';
import 'package:meta_tool/define.dart';
import 'package:path/path.dart';
import 'package:process_runner/process_runner.dart';

class UnityHotAssetCommand extends Command {
  UnityHotAssetCommand() {
    argParser.addOption('platform', help: '平台', allowed: ['ios', 'android']);
    argParser
        .addOption('build_type', help: '打包类型', allowed: ['Debug', 'Release']);
    argParser.addOption('jenkins_workspace', help: 'Jenkins 工作空间');
    argParser.addOption('branch', help: '分支');
    argParser.addOption('buildId', help: '构建ID (必填)');
  }

  @override
  FutureOr? run() async {
    final branch = argResults?['branch'];
    if (branch == null) {
      throw '分支未设置';
    }
    final buildId = argResults?['buildId'];
    if (buildId == null || buildId.toString().trim().isEmpty) {
      throw '构建ID未设置';
    }
    final platform = argResults?['platform'];
    if (platform == null) {
      throw '平台未设置';
    }
    final buildType = argResults?['build_type'] ?? 'Debug';
    final jenkinsWorkspace = argResults?['jenkins_workspace'];
    if (jenkinsWorkspace == null) {
      throw 'Jenkins 工作空间未设置';
    }

    loggerInfo('构建ID: $buildId');

    /// 执行 Unity 打包
    /// /Users/king/Documents/2022.3.55f1c1/Unity.app/Contents/MacOS/Unity -quit -batchmode -executeMethod ExportAppData.export -nographics -projectPath ./
    final appHomeDir = AppHomeDir(Directory.current.path);
    final env = loadAppEnvironment(appHomeDir);
    print(env);
    final unityProjectPath = switch (platform) {
      'ios' => env['IOS_UNITY_PATH'],
      'android' => env['ANDROID_UNITY_PATH'],
      _ => throw '平台不支持',
    };
    if (unityProjectPath == null) {
      throw '找不到平台对应的 Unity 项目路径';
    }

    /// 如果开启skipGitPull，则跳过Git操作，直接使用本地代码
    if (skipGitPull) {
      loggerInfo('跳过Git操作模式，使用本地代码');
    } else {
      await switchBranch(unityProjectPath, branch);
    }
    final unityEnginePath = env['UNITY_ENGINE_PATH'];
    if (unityEnginePath == null) {
      throw '找不到 Unity 引擎路径';
    }
    final methodName = switch (buildType) {
      'Debug' => 'ExportAppData.exportDebugHotAsset',
      'Release' => 'ExportAppData.exportReleaseHotAsset',
      _ => throw '平台不支持',
    };
    final result = await ProcessRunner().runProcess(
      [
        unityEnginePath,
        '-quit',
        '-batchmode',
        '-executeMethod',
        methodName,
        '-nographics',
        '-projectPath',
        './',
      ],
      workingDirectory: Directory(unityProjectPath),
      printOutput: true,
    );
    final stdout = result.stdout;
    bool isSuccess = stdout.contains('Exiting batchmode successfully now!');
    if (!isSuccess) {
      throw 'Unity 打包失败';
    } else {
      loggerSuccess('Unity 打包成功');
    }
    final hotAssetPath = switch (platform) {
      'ios' => join(unityProjectPath, 'HotUpdate', buildType, 'IOS'),
      'android' => join(unityProjectPath, 'HotUpdate', buildType, 'Android'),
      _ => throw '平台不支持',
    };
    if (!Directory(hotAssetPath).existsSync()) {
      throw '找不到平台对应的 Hot Asset 路径';
    }
    final jenkinsAssetDir = Directory(join(
      jenkinsWorkspace,
      'HotUpdate',
      buildId,
    ));
    if (jenkinsAssetDir.existsSync()) {
      await jenkinsAssetDir.delete(recursive: true);
    }
    await jenkinsAssetDir.create(recursive: true);

    /// 将目录hotAssetPath下面的资源复制到jenkinsAssetDir下面
    // 跨平台复制：保持与 `cp -r <srcDir> <destDir>` 一致的行为
    // 即 destDir 下会出现一个以 srcDir basename 命名的子目录
    final copiedRoot = Directory(join(jenkinsAssetDir.path, basename(hotAssetPath)));
    await copyDirectoryRecursive(Directory(hotAssetPath), copiedRoot);
    loggerSuccess('复制资源到 Jenkins 工作空间成功');
  }

  @override
  String get description => 'Unity 热更资源打包';

  @override
  String get name => 'unity-hot-asset';
}
