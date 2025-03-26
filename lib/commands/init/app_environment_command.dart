import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:meta_tool/common.dart';
import 'package:meta_tool/define.dart';
import 'package:path/path.dart';
import 'package:prompts/prompts.dart' as prompts;

class AppEnvironmentCommand extends Command {
  @override
  String get description => '初始化打包App环境参数';

  @override
  String get name => 'app_environment';

  @override
  FutureOr? run() async {
    Map<String, String> environment = {};
    final envFile = File(join(
      appHomeDir.workspace,
      'jenkins_ci',
      'env',
      'app.env',
    ));
    if (await envFile.exists()) {
      environment = readEnvironmentFromFile(envFile.path);
    } else {
      await envFile.create(recursive: true);
    }

    _writeEnvironmentWithPrompt(
      environment,
      envFile,
      'UNITY_WORKSPACE',
      '请输入包含Unity工程的APP主目录',
    );
    _writeEnvironmentWithPrompt(
        environment, envFile, 'IOS_UNITY_PATH', '请输入IOS Unity路径');
    _writeEnvironmentWithPrompt(
      environment,
      envFile,
      'ANDROID_UNITY_PATH',
      '请输入Android Unity路径',
    );
    _writeEnvironmentWithPrompt(
      environment,
      envFile,
      'UNITY_ENGINE_PATH',
      '请输入Unity引擎路径',
    );
    _writeEnvironmentWithPrompt(
      environment,
      envFile,
      'ANDROID_GIT_URL',
      '请输入Android Git URL',
    );
    _writeEnvironmentWithPrompt(
      environment,
      envFile,
      'FLUTTER_GIT_URL',
      '请输入Flutter Git URL',
    );
    _writeEnvironmentWithPrompt(environment, envFile, 'NDK_DIR', '请输入NDK路径',
        validator: (value) {
      final ndkBuild = File(join(value, 'ndk-build'));
      if (!ndkBuild.existsSync()) {
        throw Exception('NDK路径错误');
      }
      return true;
    });
    _writeEnvironmentWithPrompt(
      environment,
      envFile,
      'SDK_DIR',
      '请输入Android SDK路径',
      validator: (value) {
        final sdkBuildTools = Directory(join(value, 'build-tools'));
        if (!sdkBuildTools.existsSync()) {
          throw Exception('Android SDK路径错误');
        }
        return true;
      },
    );
    _writeEnvironment(
      environment,
      'APP_STORE_CONNECT_API_KEY_FILEPATH',
      join(appHomeDir.workspace, 'AuthKey_KSVTNYDT6P.p8'),
      envFile,
    );
  }

  _writeEnvironmentWithPrompt(
    Map<String, String> environment,
    File envFile,
    String name,
    String prompt, {
    bool Function(String)? validator,
  }) {
    final value = environment[name] ?? prompts.get(prompt);
    if (validator != null) {
      if (!validator(value)) {
        throw Exception('输入错误');
      }
    }
    _writeEnvironment(environment, name, value, envFile);
  }

  _writeEnvironment(Map<String, String> environment, String name, String value,
      File envFile) {
    environment[name] = value;
    envFile.writeAsStringSync(
      environment.entries.map((e) => 'export ${e.key}=${e.value}').join('\n'),
    );
  }
}
