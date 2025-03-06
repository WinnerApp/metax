import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:meta_tool/common.dart';
import 'package:path/path.dart';
import 'package:process_runner/process_runner.dart';

class IpaCommand extends Command {
  @override
  String get description => '打包iOS的ipa安装包';

  @override
  String get name => 'ipa';

  IpaCommand() {
    argParser.addOption('workspace', abbr: 's', help: 'ios工程目录，默认使用当前目录');
  }

  @override
  Future<void> run() async {
    String workspace = argResults?['workspace'] ?? Directory.current.path;
    final workspaceDir = Directory(workspace);
    if (!workspaceDir.existsSync()) {
      throw Exception('workspace目录不存在: $workspace');
    }

    final podfile = File(join(workspace, 'Podfile'));
    if (!podfile.existsSync()) {
      throw Exception('Podfile文件不存在: $workspace');
    }

    await ProcessRunner(environment: {
      "CONFIGURATION": "Release",
    }).runProcess(
      ['pod', 'install', '--verbose'],
      workingDirectory: workspaceDir,
      printOutput: true,
    );

    final xcarchivePath = join(workspace, 'build', 'ios', 'Runner.xcarchive');
    // xcodebuild -workspace Runner.xcworkspace -scheme Runner -archivePath "$xcarchive_path" -configuration Release archive
    await ProcessRunner().runProcess(
      [
        'xcodebuild',
        '-workspace',
        'Runner.xcworkspace',
        '-scheme',
        'Runner',
        '-archivePath',
        xcarchivePath,
        '-configuration',
        'Release',
        'archive'
      ],
      workingDirectory: workspaceDir,
      printOutput: true,
    );
    // xcodebuild -exportArchive -archivePath "$xcarchive_path" -exportPath ../build/ios/ipa -exportOptionsPlist ExportOptions.plist
    await ProcessRunner().runProcess(
      [
        'xcodebuild',
        '-exportArchive',
        '-archivePath',
        xcarchivePath,
        '-exportPath',
        join(workspace, 'build', 'ios', 'ipa'),
        '-exportOptionsPlist',
        'ExportOptions.plist'
      ],
      workingDirectory: workspaceDir,
      printOutput: true,
    );
    loggerSuccess('ipa打包完成');
  }
}
