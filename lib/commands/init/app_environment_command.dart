import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:meta_tool/common.dart';
import 'package:meta_tool/define.dart';
import 'package:meta_tool/flutter_sdk.dart';
import 'package:path/path.dart';
import 'package:process_runner/process_runner.dart';
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
      'app',
      '.env',
    ));

    if (await envFile.exists()) {
      environment = readEnvironmentFromFile(envFile.path);
    } else {
      await envFile.create(recursive: true);
    }
    final commonEnvFile = File(join(
      appHomeDir.workspace,
      'jenkins_ci',
      'env',
      'common',
      '.env',
    ));
    if (await commonEnvFile.exists()) {
      environment.addAll(readEnvironmentFromFile(commonEnvFile.path));
    }

    final isUnityWorkspace = await _isUnityWorkspace();

    final unityWorkspace = await _writeEnvironmentWithPrompt(
      environment,
      envFile,
      'UNITY_WORKSPACE',
      '请输入包含Unity工程的APP主目录',
      readValueHandler: () async {
        return isUnityWorkspace ? Directory.current.path : null;
      },
    );

    final unityProjectDirs =
        await _findUnityProjectDirs(Directory(join(unityWorkspace, 'unity')));

    /// 从列表选择对应Unity项目
    String? chooseUnityProject(String prompt) {
      if (unityProjectDirs.isEmpty) {
        return null;
      }
      return join(
        unityWorkspace,
        'unity',
        prompts.choose(prompt, unityProjectDirs),
      );
    }

    await _writeEnvironmentWithPrompt(
      environment,
      envFile,
      'IOS_UNITY_PATH',
      '请输入IOS Unity路径',
      readValueHandler: () async {
        return chooseUnityProject('请选择iOS Unity工程');
      },
    );
    await _writeEnvironmentWithPrompt(
      environment,
      envFile,
      'ANDROID_UNITY_PATH',
      '请输入Android Unity路径',
      readValueHandler: () async {
        return chooseUnityProject('请选择Android Unity工程');
      },
    );
    final unityEnginePath = await _writeEnvironmentWithPrompt(
      environment,
      envFile,
      'UNITY_ENGINE_PATH',
      '请输入Unity引擎路径',
    );
    await _writeEnvironmentWithPrompt(
      environment,
      envFile,
      'IOS_GIT_URL',
      '请输入IOS Git URL',
    );
    await _writeEnvironmentWithPrompt(
      environment,
      envFile,
      'ANDROID_GIT_URL',
      '请输入Android Git URL',
    );
    await _writeEnvironmentWithPrompt(
      environment,
      envFile,
      'FLUTTER_GIT_URL',
      '请输入Flutter Git URL',
    );
    await _writeEnvironmentWithPrompt(
      environment,
      envFile,
      'NDK_DIR',
      '请输入NDK路径',
      readValueHandler: () async {
        if (Platform.isMacOS) {
          return join(
            File(unityEnginePath).parent.parent.parent.parent.path,
            'PlaybackEngines',
            'AndroidPlayer',
            'NDK',
          );
        } else {
          return null;
        }
      },
      validator: (value) {
        loggerDebug('NDK路径: $value');
        final ndkBuild = File(join(value, 'ndk-build'));
        if (!ndkBuild.existsSync()) {
          throw Exception('NDK路径错误');
        }
        return true;
      },
    );
    await _writeEnvironmentWithPrompt(
      environment,
      envFile,
      'FLUTTER_DIR',
      '请输入Flutter路径',
      readValueHandler: () async {
        // 优先使用工程 FVM 配置对应的 SDK，避免写入 global PATH 版本
        try {
          final flutterProjectDir = appHomeDir.flutterDir;
          if (flutterProjectDir.existsSync() &&
              hasFvmConfig(flutterProjectDir)) {
            await ensureFvmFlutterReady(flutterProjectDir);
            final sdk = await resolveFlutterSdk(flutterProjectDir);
            if (sdk.flutterRoot.isNotEmpty) {
              loggerInfo('使用工程 FVM Flutter: ${sdk.flutterRoot}');
              return sdk.flutterRoot;
            }
          }
        } catch (e) {
          loggerWarning('通过 FVM 解析 Flutter 路径失败，回退 which flutter: $e');
        }

        final flutterPath = await ProcessRunner().runProcess(
          ['which', 'flutter'],
          printOutput: true,
        ).then((e) => e.stdout.trim().replaceAll("/bin/flutter", "").trim());

        /// 如果是软连接 返回真正的路径
        final realPath = await ProcessRunner().runProcess(
          ['readlink', '-f', flutterPath],
          printOutput: true,
        ).then((e) => e.stdout.trim().trim());
        return realPath;
      },
      validator: (value) {
        final dartFile = File(join(value, 'bin', 'dart'));
        final flutterFile = File(join(value, 'bin', 'flutter'));
        return dartFile.existsSync() && flutterFile.existsSync();
      },
    );
    await _writeEnvironmentWithPrompt(
      environment,
      envFile,
      'SDK_DIR',
      '请输入Android SDK路径',
      readValueHandler: () async {
        if (Platform.isMacOS) {
          final isExitFlutter = await ProcessRunner().runProcess(
            ['which', 'flutter'],
            printOutput: true,
          ).then((e) => e.stdout.trim().isNotEmpty);
          if (!isExitFlutter) return null;
          final flutterDoctorVerbose = await ProcessRunner().runProcess(
            ['flutter', 'doctor', '-v'],
            printOutput: true,
          ).then((e) => e.stdout.trim());
          if (flutterDoctorVerbose.isEmpty) return null;
          final verbises = flutterDoctorVerbose.split('\n');
          for (final verbose in verbises) {
            if (verbose.contains('• Android SDK at')) {
              return verbose.replaceFirst('• Android SDK at', '').trim();
            }
          }
          return null;
        } else {
          return null;
        }
      },
      validator: (value) {
        loggerDebug('Android SDK路径: $value');
        final sdkBuildTools = Directory(join(value, 'build-tools'));
        if (!sdkBuildTools.existsSync()) {
          throw Exception('Android SDK路径错误');
        }
        return true;
      },
    );
    await _writeEnvironment(
      environment,
      'APP_STORE_CONNECT_API_KEY_FILEPATH',
      join(appHomeDir.workspace, 'AuthKey_KSVTNYDT6P.p8'),
      envFile,
    );
  }

  Future<String> _writeEnvironmentWithPrompt(
    Map<String, String> environment,
    File envFile,
    String name,
    String prompt, {
    bool Function(String)? validator,
    Future<String?> Function()? readValueHandler,
  }) async {
    String value = environment[name] ??
        await readValueHandler?.call() ??
        prompts.get(prompt);
    if (validator != null) {
      if (!validator(value)) {
        throw Exception('输入错误');
      }
    }
    return _writeEnvironment(environment, name, value, envFile);
  }

  Future<String> _writeEnvironment(
    Map<String, String> environment,
    String name,
    String value,
    File envFile,
  ) async {
    environment[name] = value;
    await envFile.writeAsString(
      environment.entries.map((e) => 'export ${e.key}=${e.value}').join('\n'),
    );
    return value;
  }

  /// 查找当前的路径下面是否存在Unity工程
  Future<bool> _isUnityWorkspace() async {
    final currentDir = Directory.current;
    final unityDir = Directory(join(currentDir.path, 'unity'));
    if (!await unityDir.exists()) {
      return false;
    }
    final unityProjectDirs = await _findUnityProjectDirs(unityDir);
    return unityProjectDirs.isNotEmpty;
  }

  /// 查找当前路径下面属于Unity工程的目录列表
  Future<List<String>> _findUnityProjectDirs(Directory dir) async {
    final subDirs =
        await dir.list().toList().then((e) => e.whereType<Directory>());
    final result = <String>[];
    for (final dir in subDirs) {
      final hybridClrDataDir = Directory(join(dir.path, 'HybridCLRData'));
      if (await hybridClrDataDir.exists()) {
        result.add(basename(dir.path));
      }
    }
    return result;
  }
}
