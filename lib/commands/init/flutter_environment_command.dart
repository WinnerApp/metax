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
      defaultsTo: 'framework',
    );
    argParser.addOption(
      'configuration',
      help: '构建配置,可选值:debug/release',
      allowed: ['debug', 'release'],
      defaultsTo: 'release',
    );
    argParser.addFlag(
      'isStore',
      help: '是否是发布配置',
      defaultsTo: false,
    );
    argParser.addOption(
      'androidChannel',
      help: 'Android渠道',
      defaultsTo: 'Winner',
      allowed: [
        'Winner',
        'Tencent',
        'HuaWei',
        'XiaoMi',
        'Oppo',
        'MeiZu',
        'Vivo',
        'Honor',
        'Samsung',
      ],
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
        'HuaWei',
        'XiaoMi',
        'Oppo',
        'MeiZu',
        'Vivo',
        'Honor',
        'Samsung',
      ],
      defaultValue: 'Winner',
    );
    if (argBuildType == 'framework') {
      await initFrameworkEnvironment(
        configuration: argConfiguration,
        isStore: argIsStore,
        androidChannel: argAndroidChannel,
      );
    } else if (argBuildType == 'aar') {
      await initAarEnvironment(
        configuration: argConfiguration,
        isStore: argIsStore,
        androidChannel: argAndroidChannel,
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
    );
    loggerSuccess('初始化Flutter环境完成');
  }

  /// 初始化Aar环境
  Future<void> initAarEnvironment({
    required String configuration,
    required bool isStore,
    required String androidChannel,
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
    await ProcessRunner().runProcess(
      [
        'unzip',
        aarFile.path,
        '-d',
        flutterName,
      ],
      workingDirectory: aarParentDir,
      printOutput: true,
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
    );

    /// 删除aar文件
    aarFile.deleteSync();
    await ProcessRunner().runProcess(
      [
        'zip',
        '-r',
        aarName,
        flutterName,
      ],
      workingDirectory: aarParentDir,
      printOutput: true,
    );
    flutterNameDir.deleteSync(recursive: true);
    loggerSuccess('初始化Flutter环境完成');
  }

  /// 修改dart_define.json文件
  Future<void> modifyDartDefineJsonFile({
    required File dartDefineJsonFile,
    required bool isStore,
    required String androidChannel,
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

    loggerDebug('当前最新的Flutter环境配置:');
    for (var key in json.mapValue.keys) {
      loggerDebug('$key: ${json.mapValue[key]}');
    }
    await dartDefineJsonFile
        .writeAsString(JsonEncoder.withIndent('  ').convert(json.mapValue));
  }
}
