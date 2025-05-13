import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:meta_tool/common.dart';
import 'package:path/path.dart';

class VerifyPodfileCommand extends Command {
  @override
  String get description => '验证 Podfile 是否正确';

  @override
  String get name => 'verify-podfile';

  @override
  Future<void> run() async {
    final iosDir = Directory.current;
    final podFile = File(join(iosDir.path, 'Podfile'));
    if (!podFile.existsSync()) {
      throw Exception('Podfile 不存在');
    }
    final enviroment = Platform.environment['CONFIGURATION'] ?? 'Debug';
    final frameworksDir = Directory(join(
      iosDir.path,
      'frameworks',
      'flutter',
      enviroment,
    ));
    if (!frameworksDir.existsSync()) {
      throw Exception('Flutter 框架目录不存在');
    }
    List<String> podNames = [];
    for (final file in frameworksDir.listSync()) {
      if (file is File && file.path.endsWith('.podspec')) {
        final fileName = basenameWithoutExtension(file.path);
        podNames.add(fileName);
      }
    }
    List<String> alreadyPodNames = [];
    bool canBeginParse = false;
    for (final line in podFile.readAsLinesSync()) {
      if (line.contains('[flutter_pod_gen_start]')) {
        canBeginParse = true;
        continue;
      }
      if (line.contains('[flutter_pod_gen_end]')) {
        canBeginParse = false;
        continue;
      }
      if (canBeginParse && line.contains('pod ')) {
        final regex = RegExp(r"'.*'");
        final match = regex.allMatches(line);
        if (match.isNotEmpty) {
          final podName = match.first.group(0)!.replaceAll('\'', '');
          alreadyPodNames.add(podName);
        }
      }
    }

    /// 对比两个数组的内容是否一致
    final diffPodNames = podNames
        .where((element) => !alreadyPodNames.contains(element))
        .toList();
    final diffAlreadyPodNames = alreadyPodNames
        .where((element) => !podNames.contains(element))
        .toList();
    if (diffPodNames.isNotEmpty || diffAlreadyPodNames.isNotEmpty) {
      loggerDebug(diffPodNames.toString());
      loggerDebug(diffAlreadyPodNames.toString());
      throw Exception(
          'Podfile 中的依赖与 Flutter 框架目录中的依赖不一致,请使用metax init generate-podfile重新生成');
    }
  }
}
