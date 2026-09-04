import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart';

class GeneratePodfileCommand extends Command {
  @override
  String get description => '生成 Podfile Flutter 库的依赖';

  @override
  String get name => 'generate-podfile';

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
    // ShorebirdFlutter.xcframework 对外仍用 Flutter.podspec，忽略错误残留的
    // ShorebirdFlutter.podspec，避免 Podfile 再声明一份引擎 pod。
    List<String> podNames = [];
    for (final file in frameworksDir.listSync()) {
      if (file is File && file.path.endsWith('.podspec')) {
        final fileName = basenameWithoutExtension(file.path);
        if (fileName == 'ShorebirdFlutter') {
          continue;
        }
        podNames.add(fileName);
      }
    }
    final hasShorebirdFlutter = Directory(
      join(frameworksDir.path, 'ShorebirdFlutter.xcframework'),
    ).existsSync();
    final hasFlutterXcframework = Directory(
      join(frameworksDir.path, 'Flutter.xcframework'),
    ).existsSync();
    // 本地已有引擎 xcframework 时用 :path；仅远程 Flutter.podspec（--cocoapods）时用 :podspec。
    final useLocalFlutterPath = hasShorebirdFlutter || hasFlutterXcframework;
    List<String> startTexts = [];
    List<String> endTexts = [];
    bool canAddInStartTexts = true;
    bool canAddInEndTexts = false;
    for (final line in podFile.readAsLinesSync()) {
      if (canAddInEndTexts) {
        endTexts.add(line);
      }
      if (line.contains('[flutter_pod_gen_start]')) {
        canAddInStartTexts = false;
        continue;
      }
      if (line.contains('[flutter_pod_gen_end]')) {
        canAddInEndTexts = true;
        continue;
      }
      if (canAddInStartTexts) {
        startTexts.add(line);
      }
    }

    List<String> newFlutterPodsTexts = [
      '    # [flutter_pod_gen_start]',
      "    flutter_build_mode = ENV['CONFIGURATION'] || 'Debug'",
      '    flutter_path = "./frameworks/flutter/#{flutter_build_mode}"',
      '    puts "当前依赖Flutter模块静态库路径#{flutter_path}"',
      ...podNames.map((e) {
        if (e == 'Flutter') {
          if (useLocalFlutterPath) {
            return "    pod 'Flutter', :path => \"#{flutter_path}\"";
          }
          return "    pod 'Flutter', :podspec => \"#{flutter_path}\"";
        }
        return "    pod '$e', :path => \"#{flutter_path}\"";
      }),
      '    # [flutter_pod_gen_end]',
    ];
    final lines = [
      ...startTexts,
      ...newFlutterPodsTexts,
      ...endTexts,
    ];
    podFile.writeAsStringSync(lines.join('\n'));
    print('Podfile 生成成功');
  }
}
