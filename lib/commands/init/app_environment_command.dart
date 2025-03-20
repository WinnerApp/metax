import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:meta_tool/common.dart';
import 'package:path/path.dart';
import 'package:prompts/prompts.dart' as prompts;

class AppEnvironmentCommand extends Command {
  @override
  String get description => '初始化打包App环境参数';

  @override
  String get name => 'app_environment';

  AppEnvironmentCommand() {
    argParser.addOption(
      'workspace',
      help: 'App工作目录',
      defaultsTo: Directory.current.path,
    );
  }

  @override
  FutureOr? run() async {
    final workspace = argResults?['workspace'] as String;
    Map<String, String> environment = {};
    final envFile = File(join(workspace, 'jenkins_ci', 'env', 'app.env'));
    if (await envFile.exists()) {
      environment = await readEnvironmentFromFile(envFile.path);
    } else {
      await envFile.create(recursive: true);
    }

    final unityWorkspace =
        environment['UNITY_WORKSPACE'] ?? prompts.get('请输入包含Unity工程 APP主目录');
    environment['UNITY_WORKSPACE'] = unityWorkspace;
    final iosUnityPath =
        environment['IOS_UNITY_PATH'] ?? prompts.get('请输入IOS Unity路径');
    environment['IOS_UNITY_PATH'] = iosUnityPath;
    final androidUnityPath =
        environment['ANDROID_UNITY_PATH'] ?? prompts.get('请输入Android Unity路径');
    environment['ANDROID_UNITY_PATH'] = androidUnityPath;
    final unityEnginePath =
        environment['UNITY_ENGINE_PATH'] ?? prompts.get('请输入Unity引擎路径');
    environment['UNITY_ENGINE_PATH'] = unityEnginePath;
    final iosGitUrl =
        environment['IOS_GIT_URL'] ?? prompts.get('请输入IOS Git URL');
    environment['IOS_GIT_URL'] = iosGitUrl;
    final androidGitUrl =
        environment['ANDROID_GIT_URL'] ?? prompts.get('请输入Android Git URL');
    environment['ANDROID_GIT_URL'] = androidGitUrl;
    final flutterGitUrl =
        environment['FLUTTER_GIT_URL'] ?? prompts.get('请输入Flutter Git URL');
    environment['FLUTTER_GIT_URL'] = flutterGitUrl;
    await envFile.writeAsString(environment.entries
        .map((e) => 'export ${e.key}=${e.value}')
        .join('\n'));
  }
}
