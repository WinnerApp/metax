import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:meta_tool/appwrite_environment.dart';
import 'package:meta_tool/appwrite_server.dart';
import 'package:meta_tool/common.dart';
import 'package:meta_tool/define.dart';
import 'package:meta_tool/meta_ota.dart';
import 'package:process_runner/process_runner.dart';

/// 查询 Appwrite 上一版打包记录后，委托 `meta_ota check-ota` 判断是否支持热更。
///
/// 唯一对外形态：
/// `metax check-ota --platform ios --buildName 1.0.0 --json`
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
    _log(
      '上一版打包: $version (id=${buildDoc.$id} '
      'melos_branch=${buildDoc.data['melos_branch']})',
      jsonMode: jsonMode,
    );

    final bin = await resolveMetaOtaBin();
    final args = <String>[
      'check-ota',
      '--flutter',
      flutterDir.path,
      '--version',
      version,
      '--json',
      '--no-write',
    ];
    if (platform == 'android' && appHomeDir.androidDir.existsSync()) {
      args.addAll(['--android', appHomeDir.androidDir.path]);
    }
    if (platform == 'ios' && appHomeDir.iosDir.existsSync()) {
      args.addAll(['--ios', appHomeDir.iosDir.path]);
    }

    _log('委托: $bin ${args.join(' ')}', jsonMode: jsonMode);
    final result = await ProcessRunner().runProcess(
      [bin, ...args],
      workingDirectory: flutterDir,
      printOutput: false,
      failOk: true,
    );

    final metaJson = _parseLastJsonObject(result.stdout);
    if (metaJson == null) {
      final detail = result.stderr.trim().isNotEmpty
          ? result.stderr.trim()
          : result.stdout.trim();
      throw Exception(
        'meta_ota check-ota 未返回 JSON（exit=${result.exitCode}）'
        '${detail.isEmpty ? '' : ': $detail'}',
      );
    }

    final otaSupported = metaJson['ota_supported'] == true;
    final output = <String, dynamic>{
      'ota_supported': otaSupported,
      'platform': platform,
      'version': version,
      'build_name': recordedName,
      'build_number': buildNumber,
      if (metaJson['baseline_source'] != null)
        'baseline_source': metaJson['baseline_source'],
      if (metaJson['blocking_change_count'] != null)
        'blocking_change_count': metaJson['blocking_change_count'],
      if (metaJson['patchable_change_count'] != null)
        'patchable_change_count': metaJson['patchable_change_count'],
      if (metaJson['asset_change_count'] != null)
        'asset_change_count': metaJson['asset_change_count'],
      if (metaJson['change_count'] != null)
        'change_count': metaJson['change_count'],
      if (metaJson['has_baseline'] != null)
        'has_baseline': metaJson['has_baseline'],
    };

    if (jsonMode) {
      stdout.writeln(jsonEncode(output));
    } else {
      loggerInfo(
        'ota_supported=$otaSupported version=$version platform=$platform',
      );
      if (!otaSupported) {
        loggerWarning(
          '当前工程相对 $version 不支持热更'
          '（blocking=${output['blocking_change_count']} '
          'patchable=${output['patchable_change_count']}）',
        );
      } else {
        loggerSuccess('当前工程相对 $version 支持热更');
      }
    }

    // 与 meta_ota 对齐：0 支持 / 2 不支持；其它非 0 视为错误
    if (result.exitCode != 0 && result.exitCode != 2) {
      throw Exception(
        'meta_ota check-ota 失败 exit=${result.exitCode}: '
        '${result.stderr.trim()}',
      );
    }
    exit(otaSupported ? 0 : 2);
  }

  Map<String, dynamic>? _parseLastJsonObject(String text) {
    for (final line in text.split('\n').reversed) {
      final trimmed = line.trim();
      if (!trimmed.startsWith('{') || !trimmed.endsWith('}')) continue;
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map<String, dynamic>) return decoded;
        if (decoded is Map) {
          return Map<String, dynamic>.from(decoded);
        }
      } catch (_) {
        continue;
      }
    }
    return null;
  }
}
