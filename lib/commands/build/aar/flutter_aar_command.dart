import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart';
import 'package:process_runner/process_runner.dart';

class FlutterAarCommand extends Command {
  @override
  String get description => '打包flutter aar';

  @override
  String get name => 'flutter';

  FlutterAarCommand() {
    argParser.addOption('workspace', abbr: 's', help: 'flutter工程目录，默认使用当前目录');
    argParser.addOption(
      'configuration',
      abbr: 'c',
      help: 'flutter工程配置，debug/release',
      mandatory: true,
      allowed: ['debug', 'release'],
    );
    argParser.addFlag(
      'clear',
      abbr: 'c',
      help: '是否清除缓存',
      defaultsTo: false,
    );
  }

  @override
  Future<void> run() async {
    final workspace = argResults?['workspace'] ?? Directory.current.path;
    final configuration = argResults?['configuration'];
    final clear = argResults?['clear'];
    final workspaceDir = Directory(workspace);
    final pubspecFile = File(join(workspaceDir.path, 'pubspec.yaml'));
    if (!pubspecFile.existsSync()) {
      throw Exception('pubspec.yaml文件不存在: ${pubspecFile.path}');
    }
    if (clear) {
      await ProcessRunner().runProcess(
        ['flutter', 'clean'],
        workingDirectory: workspaceDir,
        printOutput: true,
      );
    }

    // flutter pub get
    await ProcessRunner().runProcess(
      ['flutter', 'pub', 'get'],
      workingDirectory: workspaceDir,
      printOutput: true,
    );

    final androidConfigDir =
        File(join(workspaceDir.path, 'buildConfigs', 'android'));
    if (!androidConfigDir.existsSync()) {
      throw Exception('buildConfigs/android目录不存在: ${androidConfigDir.path}');
    }

    final toConfigDir = Directory(join(workspace, '.android'));
    if (!toConfigDir.existsSync()) {
      throw Exception('.android目录不存在: ${toConfigDir.path}');
    }

    /// cp -r -f "$android_config_dir"/* "$generate_android_dir"
    await ProcessRunner().runProcess(
      ['cp', '-r', '-f', "${androidConfigDir.path}/*", toConfigDir.path],
      workingDirectory: workspaceDir,
      printOutput: true,
    );

    if (configuration == 'debug') {
      /// flutter build aar --no-profile --no-release --verbose
      await ProcessRunner().runProcess(
        [
          'flutter',
          'build',
          'aar',
          '--no-profile',
          '--no-release',
          '--verbose'
        ],
        workingDirectory: workspaceDir,
        printOutput: true,
      );
    } else {
      /// flutter build aar --no-debug --no-profile --verbose
      await ProcessRunner().runProcess(
        [
          'flutter',
          'build',
          'aar',
          '--no-debug',
          '--no-profile',
          '--verbose',
        ],
        workingDirectory: workspaceDir,
        printOutput: true,
      );
    }
  }
}
