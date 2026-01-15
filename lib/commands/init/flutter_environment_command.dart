import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:darty_json_safe/darty_json_safe.dart';
import 'package:meta_tool/argument_get.dart';
import 'package:meta_tool/common.dart';
import 'package:meta_tool/define.dart';
import 'package:path/path.dart';
import 'package:process_runner/process_runner.dart';

class FlutterEnvironmentCommand extends Command {
  @override
  String get description => '初始化Flutter Framework/Aar环境';

  @override
  String get name => 'flutter_environment';

  FlutterEnvironmentCommand() {
    argParser.addOption(
      'buildType',
      help: '构建类型,可选值:framework/aar',
      allowed: ['framework', 'aar'],
    );
    argParser.addOption(
      'configuration',
      help: '构建配置,可选值:debug/release',
      allowed: ['debug', 'release'],
    );
    argParser.addFlag(
      'isStore',
      help: '是否是发布配置',
    );
    argParser.addOption(
      'androidChannel',
      help: 'Android渠道',
      allowed: [
        'Winner',
        'Tencent',
        'Huawei',
        'Xiaomi',
        'Oppo',
        'Meizu',
        'Vivo',
        'Honor',
        'Samsung',
      ],
    );
    argParser.addOption(
      'branchConfig',
      help: '分支配置',
    );
  }

  @override
  Future<void> run() async {
    final argBuildType = ArgumentGet(argResults).getString(
      'buildType',
      '构建类型,可选值:framework/aar',
      allowed: ['framework', 'aar'],
    );
    final argConfiguration = ArgumentGet(argResults).getString(
      'configuration',
      '构建配置,可选值:debug/release',
      allowed: ['debug', 'release'],
    );
    final argIsStore = ArgumentGet(argResults).getBool(
      'isStore',
      '是否是发布配置',
      defaultValue: false,
    );
    final argAndroidChannel = ArgumentGet(argResults).getString(
      'androidChannel',
      'Android渠道',
      allowed: [
        'Winner',
        'Tencent',
        'Huawei',
        'Xiaomi',
        'Oppo',
        'Meizu',
        'Vivo',
        'Honor',
        'Samsung',
      ],
      defaultValue: 'Winner',
    );
    final branchConfig = JSON(argResults?['branchConfig']).mapValue;
    if (argBuildType == 'framework') {
      await initFrameworkEnvironment(
        configuration: argConfiguration,
        isStore: argIsStore,
        androidChannel: argAndroidChannel,
        branchConfig: branchConfig,
      );
    } else if (argBuildType == 'aar') {
      await initAarEnvironment(
        configuration: argConfiguration,
        isStore: argIsStore,
        androidChannel: argAndroidChannel,
        branchConfig: branchConfig,
      );
    } else {
      throw ArgumentError('构建类型错误,可选值:framework/aar');
    }
  }

  /// 初始化Framework环境
  Future<void> initFrameworkEnvironment({
    required String configuration,
    required bool isStore,
    required String androidChannel,
    required Map branchConfig,
  }) async {
    // frameworks/flutter/Release/App.xcframework/ios-arm64/App.framework/flutter_assets/assets/dart_define.json
    final dartDefineJsonFile = File(join(
      appHomeDir.iosDir.path,
      'frameworks',
      'flutter',
      configuration == 'debug' ? 'Debug' : 'Release',
      'App.xcframework',
      'ios-arm64',
      'App.framework',
      'flutter_assets',
      'assets',
      'dart_define.json',
    ));
    await modifyDartDefineJsonFile(
      dartDefineJsonFile: dartDefineJsonFile,
      isStore: isStore,
      androidChannel: androidChannel,
      branchConfig: branchConfig,
    );
    loggerSuccess('初始化Flutter环境完成');
  }

  /// 初始化Aar环境
  Future<void> initAarEnvironment({
    required String configuration,
    required bool isStore,
    required String androidChannel,
    required Map branchConfig,
  }) async {
    final flutterName = 'flutter_$configuration';
    final aarName = '$flutterName-1.0.aar';
    // aar/flutter/outputs/repo/com/winner/meta_flutter/flutter_release/1.0/flutter_release-1.0.aar
    final aarFile = File(join(
      appHomeDir.androidDir.path,
      'aar',
      'flutter',
      'outputs',
      'repo',
      'com',
      'winner',
      'meta_flutter',
      flutterName,
      '1.0',
      aarName,
    ));
    if (!aarFile.existsSync()) {
      throw ArgumentError('aar文件不存在(${aarFile.path})');
    }

    final aarParentDir = aarFile.parent;

    final flutterNameDir = Directory(join(
      aarParentDir.path,
      flutterName,
    ));
    if (flutterNameDir.existsSync()) {
      flutterNameDir.deleteSync(recursive: true);
    }

    /// 解压当前aar到指定目录
    await copyZipToDir(
      aarFile.path,
      Directory(join(aarParentDir.path, flutterName)),
    );
    // assets/flutter_assets/assets/dart_define.json
    final dartDefineJsonFile = File(join(
      aarParentDir.path,
      flutterName,
      'assets',
      'flutter_assets',
      'assets',
      'dart_define.json',
    ));
    await modifyDartDefineJsonFile(
      dartDefineJsonFile: dartDefineJsonFile,
      isStore: isStore,
      androidChannel: androidChannel,
      branchConfig: branchConfig,
    );

    // jar cvf flutter_release-1.0.aar -c flutter_release-1.0 .
    await ProcessRunner().runProcess(
      [
        'jar',
        'cvf',
        aarName,
        '-C',
        flutterName,
        '.',
      ],
      workingDirectory: aarParentDir,
      printOutput: true,
    );

    /// zip -r flutter_release-1.0.aar .
    await ProcessRunner().runProcess(
      [
        'zip',
        '-r',
        aarName,
        '.',
      ],
      workingDirectory: flutterNameDir,
      printOutput: true,
    );
    await ProcessRunner().runProcess(
      [
        'cp',
        '-rf',
        aarName,
        aarFile.path,
      ],
      workingDirectory: flutterNameDir,
      printOutput: true,
    );
    await ProcessRunner().runProcess(
      [
        'rm',
        '-rf',
        flutterNameDir.path,
      ],
      workingDirectory: aarParentDir,
      printOutput: true,
    );
    loggerSuccess('初始化Flutter环境完成');
  }

  /// 修改dart_define.json文件
  Future<void> modifyDartDefineJsonFile({
    required File dartDefineJsonFile,
    required bool isStore,
    required String androidChannel,
    required Map branchConfig,
  }) async {
    if (!dartDefineJsonFile.existsSync()) {
      throw ArgumentError('dart_define.json文件不存在(${dartDefineJsonFile.path})');
    }
    final json = JSON(await dartDefineJsonFile.readAsString());
    bool debugInvertOversizedImages = false;
    bool isOpenDioLog = true;
    bool debugYunDun = false;
    bool enableLog = true;
    bool showRestoreParams = false;
    bool isStoreVersion = false;
    String environment = 'sit';
    String channel = androidChannel;
    bool enableFlutterError = false;
    bool enableUnityOpenTime = false;
    bool enableSensorsLog = false;
    if (isStore) {
      isStoreVersion = true;
      environment = 'release';
    }
    json['debugInvertOversizedImages'] = debugInvertOversizedImages;
    json['isOpenDioLog'] = isOpenDioLog;
    json['debugYunDun'] = debugYunDun;
    json['enableLog'] = enableLog;
    json['showRestoreParams'] = showRestoreParams;
    json['isStoreVersion'] = isStoreVersion;
    json['environment'] = environment;
    json['androidChannel'] = channel;
    json['enableFlutterError'] = enableFlutterError;
    json['enableUnityOpenTime'] = enableUnityOpenTime;
    json['enableSensorsLog'] = enableSensorsLog;
    if (branchConfig.isNotEmpty) {
      json['branchConfig'] = branchConfig;
    }

    loggerDebug('当前最新的Flutter环境配置:');
    for (var key in json.mapValue.keys) {
      loggerDebug('$key: ${json.mapValue[key]}');
    }
    await dartDefineJsonFile
        .writeAsString(JsonEncoder.withIndent('  ').convert(json.mapValue));
  }
}
