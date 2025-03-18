import 'dart:io';

import 'package:meta_tool/common.dart';
import 'package:path/path.dart';
import 'package:process_runner/process_runner.dart';

class FixIosUnityCache {
  final String root;
  final String iosUnityPath;

  FixIosUnityCache({
    required this.root,
    required this.iosUnityPath,
  });

  Future<bool> fix() async {
    /// 修复iOS不支持BitCode
    loggerDebug('修复iOS不支持BitCode');

    final lineTexts = await File(projectPath).readAsLines();
    for (int i = 0; i < lineTexts.length; i++) {
      final lineText = lineTexts[i];
      if (containsBitCode(lineText)) {
        final newText = lineText.replaceAll(
          'ENABLE_BITCODE = YES',
          'ENABLE_BITCODE = false',
        );
        lineTexts[i] = newText;
      }
    }
    await File(projectPath).writeAsString(lineTexts.join('\n'));
    loggerSuccess('修复iOS不支持BitCode完毕!');

    if (!await Directory(iosBuidDir).exists()) {
      loggerError('$iosBuidDir路径不存在,请先通过Unity导出包!');
      return false;
    }

    /// 删除之前的缓存
    final buildDir = Directory(join(iosBuidDir, 'build'));
    if (await buildDir.exists()) {
      await buildDir.delete(recursive: true);
    }
    loggerDebug('修复 libil2cpp.a 报错');
    await ProcessRunner().runProcess(
      [
        'bash',
        'build_libil2cpp.sh',
      ],
      workingDirectory: Directory(iosBuidDir),
    );
    final libil2cppAFile = File(join(iosBuidDir, 'build', 'libil2cpp.a'));
    if (!await libil2cppAFile.exists()) {
      loggerError('${libil2cppAFile.path}路径不存在!');
      return false;
    }

    if (await libil2cppAFile.length() < 50 * 1024 * 1024) {
      /// 如果大小于50M则代表文件存在问题
      loggerError('${libil2cppAFile.path}文件异常请重新生成libil2cpp.a!');
      return false;
    }

    await libil2cppAFile.copy(toLibil2cppPath);
    loggerSuccess('修复 libil2cpp.a 报错完毕!');
    return true;
  }

  String get projectPath => join(
        root,
        'ios',
        'UnityLibrary',
        'Unity-iPhone.xcodeproj',
        'project.pbxproj',
      );

  bool containsBitCode(String content) {
    return content.contains('ENABLE_BITCODE = YES');
  }

  String get iosBuidDir => join(
        iosUnityPath,
        'HybridCLRData',
        'iOSBuild',
      );

  String get toLibil2cppPath => join(
        root,
        'ios',
        'UnityLibrary',
        'Libraries',
        'libil2cpp.a',
      );
}
