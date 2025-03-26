import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:meta_tool/common.dart';
import 'package:meta_tool/define.dart';
import 'package:meta_tool/unity_environment.dart';
import 'package:process_runner/process_runner.dart';
import 'package:prompts/prompts.dart' as prompts;

class InitCacheCommand extends Command {
  @override
  String get description => '初始化缓存';

  @override
  String get name => 'cache';

  @override
  FutureOr? run() async {
    final unityEnvironment = UnityEnvironment.fromEnvironment(appHomeDir);
    loggerDebug('正在初始化iOS Flutter静态库');
    await initFlutterStaticResource(buildPlatform: 'ios');
    loggerDebug('正在初始化iOS Unity静态库');
    await initUnityStaticResource(
      buildPlatform: 'ios',
      unityWorkspace: unityEnvironment.iosUnityWorkspace,
    );
    loggerDebug('正在初始化Android Flutter静态库');
    await initFlutterStaticResource(buildPlatform: 'android');
    loggerDebug('正在初始化Android Unity静态库');
    await initUnityStaticResource(
      buildPlatform: 'android',
      unityWorkspace: unityEnvironment.androidUnityWorkspace,
    );
    loggerDebug('初始化缓存完成');
  }

  /// 初始化flutter静态资源
  Future<void> initFlutterStaticResource({
    required String buildPlatform,
  }) async {
    final flutterBranch = await getCurrentBranch(appHomeDir.flutterDir.path);
    final isStore = prompts.choose('是否应用市场缓存', [
      'true',
      'false',
    ]);
    late String buildConfiguration;
    if (isStore == 'true') {
      buildConfiguration = 'release';
    } else {
      buildConfiguration = prompts.choose('请选择构建', [
        'debug',
        'release',
      ])!;
    }
    await ProcessRunner().runProcess(
      [
        'metax',
        'cache',
        'use',
        '--buildPlatform',
        buildPlatform,
        '--buildConfiguration',
        buildConfiguration,
        '--buildLibrary',
        'flutter',
        '--buildType',
        buildPlatform == 'ios' ? 'framework' : 'aar',
        '--branch',
        flutterBranch,
        '--isStore',
        isStore!,
      ],
      workingDirectory: Directory(appHomeDir.workspace),
      printOutput: true,
    );
  }

  /// 初始化unity静态资源
  Future<void> initUnityStaticResource({
    required String buildPlatform,
    required String unityWorkspace,
  }) async {
    final unityBranch = await getCurrentBranch(unityWorkspace);
    final buildId = await getUnityBuildVersion(unityWorkspace);
    await ProcessRunner().runProcess(
      [
        'metax',
        'cache',
        'use',
        '--buildPlatform',
        buildPlatform,
        '--buildConfiguration',
        'release',
        '--buildLibrary',
        'unity',
        '--buildType',
        buildPlatform == 'ios' ? 'framework' : 'aar',
        '--unityBranch',
        unityBranch,
        '--buildId',
        buildId.toString(),
        '--isStore',
        'true',
      ],
      workingDirectory: Directory(appHomeDir.workspace),
      printOutput: true,
    );
  }
}
