import 'dart:async';

import 'package:args/command_runner.dart';
import 'package:meta_tool/argument_get.dart';
import 'package:meta_tool/common.dart';
import 'package:meta_tool/define.dart';
import 'package:process_runner/process_runner.dart';

/// 根据指定 Unity 分支导出 Unity 缓存，并按平台打包对应产物（iOS Framework / Android AAR）并上传
class UnityBranchBuildCommand extends Command {
  @override
  String get description => '根据指定 Unity 分支导出 Unity 缓存，并按平台打包对应产物并上传';

  @override
  String get name => 'unity_branch_build';

  UnityBranchBuildCommand() {
    argParser.addOption(
      'platform',
      help: '构建平台：ios / android',
      allowed: ['ios', 'android'],
    );
    argParser.addOption(
      'unityBranch',
      help: 'Unity 分支名称，指定后会切换到对应分支并使用最新代码',
    );
  }

  @override
  FutureOr<void>? run() async {
    final platform = ArgumentGet(argResults).getString(
      'platform',
      '请选择平台（ios / android）',
      allowed: ['ios', 'android'],
    );
    final unityBranch = argResults?['unityBranch'] as String?;
    if (unityBranch == null || unityBranch.isEmpty) {
      throw '请通过 --unityBranch 指定 Unity 分支';
    }

    final runner = ProcessRunner();

    loggerInfo(
      '开始根据 Unity 分支 $unityBranch 导出 Unity 缓存并按平台 $platform 打包上传...',
    );

    if (platform == 'ios') {
      /// 1. iOS：先根据分支导出最新 UnityLibrary 并上传缓存
      await runner.runProcess(
        [
          'metax',
          'build',
          'unity_cache',
          'ios',
          '--unityBranch',
          unityBranch,
          '--isUpload',
          '--forceUpdate',
        ],
        workingDirectory: appHomeDir.directory,
        printOutput: true,
      );

      /// 2. 再打包 Unity Framework，并上传缓存
      await runner.runProcess(
        [
          'metax',
          'build',
          'framework',
          'unity',
          '--forceUpdate',
          '--isUpload',
        ],
        workingDirectory: appHomeDir.directory,
        printOutput: true,
      );

      loggerSuccess(
        '根据 Unity 分支 $unityBranch 打包并上传 Unity Framework 完成!',
      );
    } else if (platform == 'android') {
      /// 1. Android：先根据分支导出最新 unityLibrary 并上传缓存
      await runner.runProcess(
        [
          'metax',
          'build',
          'unity_cache',
          'android',
          '--unityBranch',
          unityBranch,
          '--isUpload',
          '--forceUpdate',
        ],
        workingDirectory: appHomeDir.directory,
        printOutput: true,
      );

      /// 2. 再打包 Unity AAR，并上传缓存
      await runner.runProcess(
        [
          'metax',
          'build',
          'aar',
          'unity',
          '--forceUpdate',
          '--isUpload',
        ],
        workingDirectory: appHomeDir.directory,
        printOutput: true,
      );

      loggerSuccess(
        '根据 Unity 分支 $unityBranch 打包并上传 Unity AAR 完成!',
      );
    } else {
      throw '不支持的平台: $platform';
    }
  }
}
