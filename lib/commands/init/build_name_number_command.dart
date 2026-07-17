import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:meta_tool/argument_get.dart';
import 'package:meta_tool/common.dart';
import 'package:meta_tool/define.dart';
import 'package:path/path.dart';

class BuildNameNumberCommand extends Command {
  @override
  String get description => '设置构建名称和版本号';

  @override
  String get name => 'build_name_number';

  BuildNameNumberCommand() {
    argParser.addOption(
      'platform',
      help: '平台',
      allowed: ['ios', 'android', 'ohos'],
    );
    argParser.addOption('buildName', help: '构建名称');
    argParser.addOption('buildNumber', help: '构建版本号');
  }

  @override
  FutureOr? run() async {
    final platform = ArgumentGet(argResults).getString(
      'platform',
      '设置平台',
      allowed: ['ios', 'android', 'ohos'],
    );
    final buildName = ArgumentGet(argResults).getString(
      'buildName',
      '设置构建名称',
    );
    final buildNumber = ArgumentGet(argResults).getString(
      'buildNumber',
      '设置构建版本号',
    );
    if (platform == 'ohos') {
      await _setOhosVersion(buildName, buildNumber);
    } else {
      File environmentFile = switch (platform) {
        'ios' => File(
            join(
              appHomeDir.iosDir.path,
              // ios/Flutter/Generated.xcconfig
              'Flutter',
              'Generated.xcconfig',
            ),
          ),
        'android' => File(join(
            appHomeDir.androidDir.path,
            // android/local.properties
            'local.properties',
          )),
        _ => throw Exception('平台错误'),
      };
      if (!environmentFile.existsSync()) {
        throw Exception('文件不存在:${environmentFile.path}');
      }
      if (platform == 'ios') {
        await writeEnvironmentValueInFile(
          environmentFile.path,
          'FLUTTER_BUILD_NAME',
          buildName,
        );
        await writeEnvironmentValueInFile(
          environmentFile.path,
          'FLUTTER_BUILD_NUMBER',
          buildNumber,
        );
      } else {
        await writeEnvironmentValueInFile(
          environmentFile.path,
          'flutter.versionName',
          buildName,
        );
        await writeEnvironmentValueInFile(
          environmentFile.path,
          'flutter.versionCode',
          buildNumber,
        );
      }
    }
    loggerSuccess('设置版本号:$buildName和构建号:$buildNumber成功');
  }

  Future<void> _setOhosVersion(String buildName, String buildNumber) async {
    final appJson5 = File(join(
      appHomeDir.ohosDir.path,
      'AppScope',
      'app.json5',
    ));
    if (!appJson5.existsSync()) {
      throw Exception('文件不存在:${appJson5.path}');
    }
    var text = await appJson5.readAsString();
    if (!RegExp(r'"versionCode"\s*:').hasMatch(text) ||
        !RegExp(r'"versionName"\s*:').hasMatch(text)) {
      throw Exception('app.json5 缺少 versionCode/versionName: ${appJson5.path}');
    }
    text = text.replaceFirst(
      RegExp(r'"versionCode"\s*:\s*\d+'),
      '"versionCode": ${int.parse(buildNumber)}',
    );
    text = text.replaceFirst(
      RegExp(r'"versionName"\s*:\s*"[^"]*"'),
      '"versionName": "$buildName"',
    );
    await appJson5.writeAsString(text);
    loggerDebug('已更新 ${appJson5.path}');
  }
}
