import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:meta_tool/common.dart';
import 'package:path/path.dart';
import 'package:prompts/prompts.dart' as prompts;

/// 验证当前的 apk 是否是正式版本 是否是对应渠道的 apk
class VerifyAndroidChannelCommand extends Command {
  @override
  String get description => '验证当前的 apk 是否是正式版本 是否是对应渠道的 apk';

  @override
  String get name => 'verify-android-channel';

  VerifyAndroidChannelCommand() {
    argParser.addOption('apk', help: 'apk 文件路径');
  }

  final dartDefinePath = 'assets/flutter_assets/assets/dart_define.json';

  @override
  Future<void> run() async {
    String? apk = argResults?['apk'];
    apk ??= prompts.choose(
      '请选择校验的 APK',
      Directory.current
          .listSync(recursive: true, followLinks: false)
          .map((e) => e.path)
          .where((e) => e.endsWith('.apk'))
          .toList(),
    );
    if (apk == null) {
      throw Exception('请指定 apk 文件路径');
    }

    try {
      await _verifyApk(apk);
      loggerSuccess('验证通过');
    } catch (e, stackTrace) {
      loggerError(e.toString() + stackTrace.toString());
    }
    final assetsDir = Directory(join(Directory.current.path, 'assets'));
    if (await assetsDir.exists()) {
      await assetsDir.delete(recursive: true);
    }
  }

  Future<void> _verifyApk(String apk) async {
    final apkName = basename(apk);
    if (!apkName.endsWith('.apk')) {
      throw Exception('请指定 apk 文件路径');
    }

    final subNames = apkName.split('_');
    if (subNames.length != 3) {
      throw Exception('$apk 文件名无法解析');
    }

    final channel = subNames[0];

    loggerWarning('当前需要校验的安卓渠道为: $channel');
    // const androidManifestPath = 'AndroidManifest.xml';

    // 只需要 dart_define.json：解压到临时目录（跨平台，避免污染/误删当前目录）
    final tempDir = await Directory.systemTemp.createTemp('metax-verify-apk-');
    await copyZipToDir(apk, tempDir);

    // final androidMainfestFile =
    //     File(join(Directory.current.path, androidManifestPath));
    // if (!androidMainfestFile.existsSync()) {
    //   loggerError('$androidMainfestFile 不存在!');
    //   return;
    // }

    final dartDefineFile = File(join(tempDir.path, dartDefinePath));
    if (!dartDefineFile.existsSync()) {
      throw Exception('$dartDefineFile 不存在!');
    }

    final dartDefine = jsonDecode(dartDefineFile.readAsStringSync());
    final isStoreVersion = dartDefine['isStoreVersion'];
    if (isStoreVersion == null || !isStoreVersion) {
      throw Exception('当前 apk 不是正式版本');
    }

    final androidChannel = dartDefine['androidChannel'];
    if (androidChannel == null || androidChannel != channel) {
      throw Exception('当前 apk 不是 $channel 渠道的 apk');
    }
  }

  File getDartDefineFile(String dartDefinePath) =>
      File(join(Directory.current.path, dartDefinePath));
}
