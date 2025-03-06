import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:meta_tool/common.dart';
import 'package:path/path.dart';
import 'package:process_runner/process_runner.dart';

class FlutterFrameworkCommand extends Command {
  @override
  String get description => '编译Flutter Framework';

  @override
  String get name => 'flutter';

  FlutterFrameworkCommand() {
    argParser.addOption(
      'workspace',
      abbr: 's',
      help: 'flutter工程目录，默认使用当前目录',
    );
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
    String workspace = argResults?['workspace'] ?? Directory.current.path;
    String configuration = argResults?['configuration'];
    bool clear = argResults?['clear'];
    final pubspecFile = File(join(workspace, 'pubspec.yaml'));
    if (!pubspecFile.existsSync()) {
      throw Exception('pubspec.yaml文件不存在: ${pubspecFile.path}');
    }
    if (!await isGitRepository(workspace)) {
      throw Exception('当前目录不是git仓库: $workspace');
    }
    final branch = await getCurrentBranch(workspace);
    final commitId = await getCurrentCommitHash(workspace);
    if (clear) {
      await ProcessRunner().runProcess(
        ['flutter', 'clean'],
        workingDirectory: Directory(workspace),
      );
    }

    /// flutter pub get
    await ProcessRunner().runProcess(
      ['flutter', 'pub', 'get'],
      workingDirectory: Directory(workspace),
    );
    if (configuration == 'debug') {
      /// flutter build ios-framework --no-profile --no-release --xcframework --cocoapods --verbose
      await ProcessRunner().runProcess(
        [
          'flutter',
          'build',
          'ios-framework',
          '--no-profile',
          '--no-release',
          '--xcframework',
          '--cocoapods',
          '--verbose'
        ],
        workingDirectory: Directory(workspace),
      );
    } else {
      /// flutter build ios-framework --no-debug --no-profile --xcframework --cocoapods --verbose
      await ProcessRunner().runProcess(
        [
          'flutter',
          'build',
          'ios-framework',
          '--no-debug',
          '--no-profile',
          '--xcframework',
          '--cocoapods',
          '--verbose'
        ],
        workingDirectory: Directory(workspace),
      );
    }
  }
}
