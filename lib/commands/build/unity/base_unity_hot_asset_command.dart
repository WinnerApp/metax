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
    argParser.addOption('platform',
        help: '平台', allowed: ['ios', 'android', 'ohos']);
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
      'ohos' => env['OHOS_UNITY_PATH'],
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

    // 鸿蒙 WebGL 热更与 iOS/Android 一样走 Unity 引擎（不再用团结）。
    final unityEnginePath = env['UNITY_ENGINE_PATH'];
    if (unityEnginePath == null || unityEnginePath.trim().isEmpty) {
      throw '找不到 Unity 引擎路径（UNITY_ENGINE_PATH）';
    }

    final methodName = _resolveHotAssetMethod(
      platform: platform,
      buildType: buildType,
    );
    loggerInfo(
      'Unity 热更: platform=$platform buildType=$buildType method=$methodName',
    );

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
      // WebGL 热更产物目录仍为 Harmony（工具/上传链路写死）
      'ohos' => join(unityProjectPath, 'HotUpdate', buildType, 'Harmony'),
      _ => throw '平台不支持',
    };
    if (!Directory(hotAssetPath).existsSync()) {
      throw '找不到平台对应的 Hot Asset 路径: $hotAssetPath';
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
    // bash 复制目录到另一个目录
    await ProcessRunner().runProcess(
      ['cp', '-r', hotAssetPath, jenkinsAssetDir.path],
      printOutput: true,
    );
    loggerSuccess('复制资源到 Jenkins 工作空间成功: ${jenkinsAssetDir.path}');
  }

  /// iOS/Android：旧 HotAsset 入口；鸿蒙：WebGL 热更入口。
  String _resolveHotAssetMethod({
    required String platform,
    required String buildType,
  }) {
    if (platform == 'ohos') {
      return switch (buildType) {
        'Debug' => 'ExportAppData.BuildWebGLHotUpdate',
        'Release' => 'ExportAppData.BuildWebGLHotUpdateRelease',
        _ => throw '打包类型不支持: $buildType',
      };
    }
    return switch (buildType) {
      'Debug' => 'ExportAppData.exportDebugHotAsset',
      'Release' => 'ExportAppData.exportReleaseHotAsset',
      _ => throw '打包类型不支持: $buildType',
    };
  }

  @override
  String get description => 'Unity 热更资源打包（鸿蒙走 WebGL HotUpdate）';

  @override
  String get name => 'unity-hot-asset';
}
