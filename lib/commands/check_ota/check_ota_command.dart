import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:meta_tool/appwrite_environment.dart';
import 'package:meta_tool/appwrite_server.dart';
import 'package:meta_tool/common.dart';
import 'package:meta_tool/define.dart';
import 'package:meta_tool/flutterpatch.dart';

/// 同步工作区后，用 Flutter 目录调用 `flutterpatch check-ota` 判断是否支持热更。
///
/// 对外形态（Jenkins / 旧脚本）：
/// `metax check-ota --platform ios --buildName 1.0.0 [--branch ...] [--json]`
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
      help: '宿主版本名，如 1.0.0（未传 --release-version 时查 Appwrite 上一版打包记录）',
    );
    argParser.addOption(
      'release-version',
      help: '精确宿主版本，如 1.2.3+456；优先于仅按 --buildName 取最新一条',
    );
    argParser.addOption(
      'branch',
      help: 'Melos 分支：检测前先切主仓并同步子模块（与 metax patch 一致）',
    );
    argParser.addOption(
      'unsupported-out',
      help: '透传 flutterpatch --unsupported-out：不支持热更的文件列表 JSON 路径',
    );
    argParser.addOption(
      'supported-out',
      help: '透传 flutterpatch --supported-out：支持热更的文件列表 JSON 路径',
    );
    argParser.addOption(
      'resources-out',
      help:
          '写出资源热更配置 JSON：全量 resources + 增量 asset_changes + '
          '不支持 unsupported_asset_changes；列表为空也会写',
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
      '同步代码后按 Flutter 工程调用 flutterpatch check-ota，检测是否支持热更';

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
    final buildNameArg = (argResults?['buildName'] as String?)?.trim() ?? '';
    final releaseVersionArg =
        (argResults?['release-version'] as String?)?.trim() ?? '';
    final branch = (argResults?['branch'] as String?)?.trim() ?? '';
    final unsupportedOut =
        (argResults?['unsupported-out'] as String?)?.trim() ?? '';
    final supportedOut =
        (argResults?['supported-out'] as String?)?.trim() ?? '';
    final resourcesOut =
        (argResults?['resources-out'] as String?)?.trim() ?? '';

    if (buildNameArg.isEmpty && releaseVersionArg.isEmpty) {
      throw Exception('请提供 --release-version 或 --buildName');
    }

    await ensureGitSafeDirectory(appHomeDir.workspace);

    if (skipGitPull) {
      _log('跳过 Git 操作模式，使用本地代码', jsonMode: jsonMode);
    } else if (branch.isNotEmpty) {
      _log('同步工作区到 Melos 分支: $branch', jsonMode: jsonMode);
      await syncMelosWorkspaceToBranch(appHomeDir.workspace, branch);
    } else {
      _log('未指定 --branch，使用当前工作区代码检测', jsonMode: jsonMode);
    }

    final flutterDir = appHomeDir.flutterDir;
    if (!flutterDir.existsSync()) {
      throw Exception('Flutter 目录不存在: ${flutterDir.path}');
    }
    await ensureGitSafeDirectory(flutterDir.path);
    _log('Flutter 目录: ${flutterDir.path}（已授权 Git safe.directory）',
        jsonMode: jsonMode);

    late final String version;
    late final String recordedName;
    late final String buildNumber;
    if (releaseVersionArg.isNotEmpty) {
      version = releaseVersionArg;
      final parsed = parseFlutterPatchReleaseVersion(version);
      recordedName = parsed.buildName;
      buildNumber = parsed.buildNumber;
    } else {
      final resolved = await _resolveVersionFromBuildName(
        platform: platform,
        buildName: buildNameArg,
        jsonMode: jsonMode,
      );
      version = resolved.version;
      recordedName = resolved.buildName;
      buildNumber = resolved.buildNumber;
    }

    _log(
      '热更检测基线: $version platform=$platform flutter=${flutterDir.path}',
      jsonMode: jsonMode,
    );

    final check = await runFlutterPatchCheckOta(
      flutterDir: flutterDir,
      platform: platform,
      releaseVersion: version,
      androidDir: platform == 'android' && appHomeDir.androidDir.existsSync()
          ? appHomeDir.androidDir
          : null,
      iosDir: platform == 'ios' && appHomeDir.iosDir.existsSync()
          ? appHomeDir.iosDir
          : null,
      unsupportedOut: unsupportedOut.isEmpty ? null : unsupportedOut,
      supportedOut: supportedOut.isEmpty ? null : supportedOut,
      resourcesOut: resourcesOut.isEmpty ? null : resourcesOut,
    );

    if (check.stdout.trim().isNotEmpty) {
      _log(check.stdout.trim(), jsonMode: jsonMode);
    }
    if (check.stderr.trim().isNotEmpty) {
      stderr.writeln(check.stderr.trim());
    }

    if (check.exitCode != 0 && check.exitCode != 2) {
      throw Exception(
        'flutterpatch check-ota 失败 exit=${check.exitCode}'
        '${check.stderr.trim().isEmpty ? '' : ': ${check.stderr.trim()}'}',
      );
    }

    final otaSupported = check.otaSupported && check.exitCode == 0;

    // Prefer CLI-written --resources-out; fall back to reconstructing from JSON
    // for older flutterpatch builds that lack the flag.
    if (resourcesOut.isNotEmpty && !File(resourcesOut).existsSync()) {
      writeHotUpdatableResourcesJson(
        checkJson: check.json,
        path: resourcesOut,
        otaSupported: otaSupported,
      );
      _log('已写出资源热更配置: $resourcesOut', jsonMode: jsonMode);
    } else if (resourcesOut.isNotEmpty) {
      _log('已写出资源热更配置: $resourcesOut', jsonMode: jsonMode);
    }

    final output = <String, dynamic>{
      'ota_supported': otaSupported,
      'platform': platform,
      'version': version,
      'flutter_dir': flutterDir.path,
      'build_name': recordedName,
      'build_number': buildNumber,
      if (check.json != null) ..._pickFlutterPatchFields(check.json!),
      if (resourcesOut.isNotEmpty) 'resources_out': resourcesOut,
      if (supportedOut.isNotEmpty) 'supported_out': supportedOut,
      if (unsupportedOut.isNotEmpty) 'unsupported_out': unsupportedOut,
    };

    if (jsonMode) {
      stdout.writeln(jsonEncode(output));
    } else {
      loggerInfo(
        'ota_supported=$otaSupported version=$version platform=$platform',
      );
      if (!otaSupported) {
        loggerWarning('当前工程相对 $version 不支持热更');
      } else {
        loggerSuccess('当前工程相对 $version 支持热更');
      }
    }

    exitCode = otaSupported ? 0 : 2;
  }

  Map<String, dynamic> _pickFlutterPatchFields(Map<String, dynamic> json) {
    const keys = [
      'blocking_change_count',
      'patchable_change_count',
      'asset_change_count',
      'unsupported_asset_change_count',
      'change_count',
      'has_baseline',
      'baseline_source',
      // 全量 / 增量 / 不支持
      'resources',
      'resource_count',
      'asset_changes',
      'unsupported_asset_changes',
    ];
    final out = <String, dynamic>{};
    for (final key in keys) {
      if (json.containsKey(key)) {
        out[key] = json[key];
      }
    }
    return out;
  }

  Future<({String version, String buildName, String buildNumber})>
      _resolveVersionFromBuildName({
    required String platform,
    required String buildName,
    required bool jsonMode,
  }) async {
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
    _log(
      '上一版打包: $recordedName+$buildNumber (id=${buildDoc.$id} '
      'melos_branch=${buildDoc.data['melos_branch']})',
      jsonMode: jsonMode,
    );
    return (
      version: '$recordedName+$buildNumber',
      buildName: recordedName,
      buildNumber: buildNumber,
    );
  }
}
