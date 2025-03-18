import 'dart:async';
import 'dart:io';

import 'package:meta_tool/common.dart';
import 'package:process_runner/process_runner.dart';

class UpdateUnity {
  final String workspace;
  final String unityEnginePath;
  final UnityPlatform platform;

  UpdateUnity({
    required this.workspace,
    required this.unityEnginePath,
    required this.platform,
  });

  Future<bool> update() async {
    // /Users/king/Documents/2021.3.16f1c1/Unity.app/Contents/MacOS/unity -quit -batchmode -executeMethod ExportAppData.exportAndroid -nographics -projectPath ./
    // 看到日志[Exiting batchmode successfully now!]代表成功

    final success = await ProcessRunner().runProcess(
      [
        unityEnginePath,
        '-quit',
        '-batchmode',
        '-executeMethod',
        platform.exportMethod,
        '-nographics',
        '-projectPath',
        './'
      ],
      workingDirectory: Directory(workspace),
    ).then((e) {
      final stdout = e.stdout;
      return stdout.contains('Exiting batchmode successfully now!');
    }).catchError((e) => false);

    if (success) {
      loggerSuccess('导出$workspace最新的包成功!');
      return true;
    } else {
      loggerError('导出$workspace最新的包失败!');
      return false;
    }
  }
}

enum UnityPlatform {
  ios("ExportAppData.exportIOS"),
  android("ExportAppData.exportAndroid");

  final String exportMethod;
  const UnityPlatform(this.exportMethod);
}
