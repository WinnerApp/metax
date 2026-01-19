import 'dart:async';
import 'dart:io';

import 'package:meta_tool/common.dart';

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

    try {
      final process = await Process.start(
        unityEnginePath,
        [
          '-quit',
          '-batchmode',
          '-executeMethod',
          platform.exportMethod,
          '-nographics',
          '-projectPath',
          './'
        ],
        workingDirectory: workspace,
        mode: ProcessStartMode.normal,
      );

      final stdoutBuffer = StringBuffer();
      final stderrBuffer = StringBuffer();

      // 实时输出 stdout
      process.stdout.transform(const SystemEncoding().decoder).listen(
        (data) {
          stdout.write(data);
          stdoutBuffer.write(data);
        },
      );

      // 实时输出 stderr
      process.stderr.transform(const SystemEncoding().decoder).listen(
        (data) {
          stderr.write(data);
          stderrBuffer.write(data);
        },
      );

      final exitCode = await process.exitCode;
      final stdoutStr = stdoutBuffer.toString();
      final success = exitCode == 0 &&
          stdoutStr.contains('Exiting batchmode successfully now!');

      if (success) {
        loggerSuccess('导出$workspace最新的包成功!');
        return true;
      } else {
        loggerError('导出$workspace最新的包失败!');
        return false;
      }
    } catch (e) {
      loggerError('导出$workspace最新的包失败: $e');
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
