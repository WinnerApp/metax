import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:meta_tool/appwrite_environment.dart';
import 'package:meta_tool/appwrite_server.dart';
import 'package:meta_tool/commands/patch/patch_compat_gate.dart';
import 'package:meta_tool/commands/patch/patch_release_baseline.dart';
import 'package:meta_tool/common.dart';
import 'package:meta_tool/define.dart';

/// 查询 Appwrite 上一版打包记录后，用 [PatchCompatGate] 判断当前工程是否支持热更。
///
/// 对外形态（Jenkins / 旧脚本）：
/// `metax check-ota --platform ios --buildName 1.0.0 [--json]`
///
/// 退出码：0 支持热更 / 2 不支持 / 其它为执行失败。
class CheckOtaCommand extends Command {
  CheckOtaCommand() {
    argParser.addOption(
      'platform',
      help: '平台：ios | android',
      allowed: ['ios', 'android'],
      mandatory: true,
    );
    argParser.addOption(
      'buildName',
      help: '宿主版本名，如 1.0.0（用于查 Appwrite 上一版打包记录）',
      mandatory: true,
    );
    argParser.addFlag(
      'json',
      help: 'stdout 仅输出一行机器可读 JSON',
      defaultsTo: false,
      negatable: false,
    );
  }

  @override
  String get name => 'check-ota';

  @override
  String get description =>
      '按 platform + buildName 查上一版打包记录，并检测当前工程是否支持热更';

  void _log(String message, {required bool jsonMode}) {
    if (jsonMode) {
      stderr.writeln(message);
    } else {
      loggerInfo(message);
    }
  }

  @override
  FutureOr<void> run() async {
    final jsonMode = argResults?['json'] == true;
    final platform = (argResults?['platform'] as String).trim();
    final buildName = (argResults?['buildName'] as String).trim();
    if (buildName.isEmpty) {
      throw Exception('--buildName 不能为空');
    }

    final flutterDir = appHomeDir.flutterDir;
    if (!flutterDir.existsSync()) {
      throw Exception('Flutter 目录不存在: ${flutterDir.path}');
    }

    final buildEnv = AppwriteBuildEnvironment(appHomeDir);
    final server = AppwriteServer(
      endpoint: buildEnv.endpoint,
      projectId: buildEnv.projectId,
      apiKey: buildEnv.apiKey,
    );

    _log(
      '查询 Appwrite 打包记录: platform=$platform build_name=$buildName',
      jsonMode: jsonMode,
    );
    final buildDoc = await server.queryLatestBuildConfigByBuildName(
      databaseId: buildEnv.databaseId,
      buildConfigCollectionId: buildEnv.buildConfigCollectionId,
      platform: platform,
      buildName: buildName,
    );
    if (buildDoc == null) {
      throw Exception(
        '未找到打包记录: platform=$platform build_name=$buildName。'
        '请确认该版本曾用 metax upload 出包。',
      );
    }

    final recordedName = buildDoc.data['build_name']?.toString().trim() ?? '';
    final buildNumber = buildDoc.data['build_number']?.toString().trim() ?? '';
    if (recordedName.isEmpty || buildNumber.isEmpty) {
      throw Exception(
        '打包记录 ${buildDoc.$id} 缺少 build_name / build_number',
      );
    }
    final version = '$recordedName+$buildNumber';
    final preferMelos = buildDoc.data['melos_branch']?.toString();
    _log(
      '上一版打包: $version (id=${buildDoc.$id} '
      'melos_branch=$preferMelos)',
      jsonMode: jsonMode,
    );

    final baselines = await PatchReleaseBaselineResolver(
      appHomeDir: appHomeDir,
      platform: platform,
    ).resolve(
      releaseVersion: version,
      preferMelosBranch: preferMelos,
    );
    final result = await PatchCompatGate(appHomeDir).check(baselines);
    final output = <String, dynamic>{
      'ota_supported': result.ok,
      'platform': platform,
      'version': version,
      'build_name': recordedName,
      'build_number': buildNumber,
      'blocking_change_count': result.issues.length,
      'baseline_repo_count': result.baselines.length,
    };

    if (jsonMode) {
      stdout.writeln(jsonEncode(output));
    } else {
      loggerInfo(
        'ota_supported=${result.ok} version=$version platform=$platform',
      );
      if (!result.ok) {
        loggerWarning(result.abortMessage());
      } else {
        loggerSuccess('当前工程相对 $version 支持热更');
      }
    }

    exitCode = result.ok ? 0 : 2;
  }
}
