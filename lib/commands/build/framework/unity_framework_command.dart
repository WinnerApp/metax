import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart';
import 'package:process_runner/process_runner.dart';

class UnityFrameworkCommand extends Command {
  @override
  String get description => '打包Unity Framework';

  @override
  String get name => 'unity';

  UnityFrameworkCommand() {
    argParser.addOption('workspace', abbr: 's', help: 'unity工程目录，默认使用当前目录');
  }

  @override
  Future<void> run() async {
    final workspace = argResults?['workspace'] ?? Directory.current.path;
    final workspaceDir = Directory(workspace);
    final xcodeProjectPath = join(workspaceDir.path, 'Unity-iPhone.xcodeproj');
    if (!File(xcodeProjectPath).existsSync()) {
      throw '当前目录不是iOS Unity工程目录';
    }

    await ProcessRunner().runProcess(
      [
        'xcodebuild',
        '-project',
        'Unity-iPhone.xcodeproj',
        '-scheme',
        'UnityFramework',
        '-configuration',
        'Release',
        '-sdk',
        'iphoneos',
        'BUILD_DIR=./build',
        'BUILD_ROOT=./build',
        'DEBUG_INFORMATION_FORMAT=dwarf-with-dsym',
        'clean',
        'build'
      ],
      workingDirectory: workspaceDir,
    );
  }
}
