import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:meta_tool/common.dart';
import 'package:meta_tool/define.dart';
import 'package:path/path.dart';

class IpaCommand extends Command {
  @override
  String get description => '打包iOS的ipa安装包';

  @override
  String get name => 'ipa';

  @override
  Future<void> run() async {
    final iosDir = appHomeDir.iosDir;
    if (!iosDir.existsSync()) {
      throw Exception('ios目录不存在: ${iosDir.path}');
    }

    if (useMock) {
      await copyDirToDir(
        MockType.ipa.mockDir(appHomeDir),
        MockType.ipa.sourceCacheDir(appHomeDir),
      );
    } else {
      final podfile = File(join(iosDir.path, 'Podfile'));
      if (!podfile.existsSync()) {
        throw Exception('Podfile文件不存在: ${podfile.path}');
      }

      await runProcessChecked(
        ['pod', 'install', '--verbose'],
        workingDirectory: iosDir,
        environment: {"CONFIGURATION": "Release"},
        printOutput: true,
      );

      final xcarchivePath =
          join(iosDir.path, 'build', 'ios', 'Runner.xcarchive');
      // xcodebuild -workspace Runner.xcworkspace -scheme Runner -archivePath "$xcarchive_path" -configuration Release archive
      await runProcessChecked(
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
        workingDirectory: iosDir,
        printOutput: true,
      );
      // xcodebuild -exportArchive -archivePath "$xcarchive_path" -exportPath ../build/ios/ipa -exportOptionsPlist ExportOptions.plist
      await runProcessChecked(
        [
          'xcodebuild',
          '-exportArchive',
          '-archivePath',
          xcarchivePath,
          '-exportPath',
          join(iosDir.path, 'build', 'ios', 'ipa'),
          '-exportOptionsPlist',
          'ExportOptions.plist'
        ],
        workingDirectory: iosDir,
        printOutput: true,
      );
    }

    loggerSuccess('ipa打包完成');
  }
}
