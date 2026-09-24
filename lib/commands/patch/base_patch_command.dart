import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:meta_tool/argument_get.dart';
import 'package:meta_tool/commands/patch/patch_artifact_cache.dart';
import 'package:meta_tool/common.dart';
import 'package:meta_tool/define.dart';
import 'package:meta_tool/flutterpatch.dart';
import 'package:path/path.dart';
import 'package:process_runner/process_runner.dart';

abstract class BasePatchCommand extends Command {
  BasePatchCommand() {
    argParser.addOption(
      'release-version',
      help: '宿主版本，如 1.2.3+456，须与当初 FlutterPatch release 一致',
    );
    argParser.addOption(
      'branch',
      help: 'Melos 分支（与打包一致：切主仓并同步全部子模块后再打补丁）',
    );
    argParser.addFlag(
      'force-patch',
      help: '跳过 flutterpatch check-ota（危险，仅排障/强行热更）',
      defaultsTo: false,
      negatable: false,
    );
    argParser.addFlag(
      'check-only',
      help: '仅检测是否支持热更（跑 check-ota 并写出 JSON），不打补丁、不上传',
      defaultsTo: false,
      negatable: false,
    );
    argParser.addOption(
      'channel',
      help: '已废弃，忽略（兼容旧 Jenkins 脚本）',
    );
    argParser.addFlag(
      'useFlutterPatch',
      help: '显式启用 FlutterPatch（覆盖 yaml）',
      defaultsTo: null,
    );
    argParser.addFlag(
      'allow-asset-diffs',
      help:
          '透传 flutterpatch --allow-asset-diffs：允许补丁相对 release 有 asset 差异'
          '（asset 不会打进补丁，仅跳过拦截）',
      defaultsTo: false,
      negatable: false,
    );
    argParser.addFlag(
      'whitelist',
      help:
          '透传 flutterpatch --whitelist：写入补丁元数据，由**客户端**按 unique_ids 灰度。'
          '服务端不拦截下载。未给 --unique-ids 时客户端会全员跳过，需补 ID。'
          '全量客户端放行用 --no-whitelist',
      defaultsTo: false,
    );
    argParser.addMultiOption(
      'unique-ids',
      help:
          '透传 flutterpatch --unique-ids：白名单开启时客户端允许更新的业务 id'
          '（如用户 uid；逗号分隔或重复传参）。服务端不据此挡下载',
      splitCommas: true,
    );
    argParser.addOption(
      'unsupported-out',
      help: '透传 flutterpatch --unsupported-out：不支持热更的文件列表 JSON',
    );
    argParser.addOption(
      'supported-out',
      help: '透传 flutterpatch --supported-out：支持热更的文件/资源变更 JSON',
    );
    argParser.addOption(
      'resources-out',
      help:
          '写出资源热更配置 JSON：全量 resources + 增量 asset_changes + '
          '不支持 unsupported_asset_changes；列表为空也会写',
    );
    argParser.addFlag(
      'isUpload',
      help: '将补丁产生的完整 aar/framework 按正常打包逻辑写入本地缓存后上传云端',
      defaultsTo: true,
    );
  }

  String get otaPlatform; // android | ios
  String get flutterPatchPlatform; // aar | ios-framework

  @override
  FutureOr<void> run() async {
    final flutterDir = appHomeDir.flutterDir;
    if (!flutterDir.existsSync()) {
      throw Exception('Flutter 目录不存在: ${flutterDir.path}');
    }

    final explicit = argResults?['useFlutterPatch'] as bool?;
    final resolved = resolveUseFlutterPatch(
      appHomeDir: appHomeDir,
      explicitUseFlutterPatch: explicit,
    );
    loggerInfo('FlutterPatch: enabled=${resolved.enabled} (${resolved.reason})');
    if (!resolved.enabled) {
      throw Exception(
        '当前未启用 FlutterPatch 热更。请在 pubspec.yaml 设置 metax.shorebird_enabled: true，'
        '或传 --useFlutterPatch / FLUTTERPATCH_ENABLED=true。',
      );
    }

    if (skipGitPull) {
      loggerInfo('跳过 Git 操作模式，使用本地代码');
    } else {
      // 与打包一致：选择 Melos 分支 → 拉最新 → 同步全部子模块到执行分支
      final melosBranch = ArgumentGet(argResults).getString(
        'branch',
        '请选择Melos分支',
        allowed: await getLatestBranchList(appHomeDir.workspace),
      );
      loggerInfo('同步工作区到 Melos 分支: $melosBranch');
      await syncMelosWorkspaceToBranch(appHomeDir.workspace, melosBranch);
    }

    final releaseVersion = ArgumentGet(argResults).getString(
      'release-version',
      '请输入 release-version（如 1.2.3+456）',
    );

    final channel = (argResults?['channel'] as String?)?.trim();
    if (channel != null && channel.isNotEmpty) {
      loggerWarning('已忽略已废弃参数 --channel=$channel');
    }

    final checkOnly = argResults?['check-only'] == true;
    final forcePatch = argResults?['force-patch'] == true;
    if (checkOnly && forcePatch) {
      throw Exception('--check-only 与 --force-patch 不能同时使用');
    }

    final unsupportedOut =
        (argResults?['unsupported-out'] as String?)?.trim() ?? '';
    final supportedOut =
        (argResults?['supported-out'] as String?)?.trim() ?? '';
    final resourcesOut =
        (argResults?['resources-out'] as String?)?.trim() ?? '';

    if (!forcePatch) {
      await ensureGitSafeDirectory(flutterDir.path);
      loggerInfo(
        '热更预检: flutterpatch check-ota version=$releaseVersion '
        'platform=$otaPlatform'
        '${checkOnly ? ' (check-only)' : ''}',
      );
      final check = await runFlutterPatchCheckOta(
        flutterDir: flutterDir,
        platform: otaPlatform,
        releaseVersion: releaseVersion,
        androidDir: otaPlatform == 'android' && appHomeDir.androidDir.existsSync()
            ? appHomeDir.androidDir
            : null,
        iosDir: otaPlatform == 'ios' && appHomeDir.iosDir.existsSync()
            ? appHomeDir.iosDir
            : null,
        unsupportedOut: unsupportedOut.isEmpty ? null : unsupportedOut,
        supportedOut: supportedOut.isEmpty ? null : supportedOut,
        resourcesOut: resourcesOut.isEmpty ? null : resourcesOut,
      );
      if (check.stdout.trim().isNotEmpty) {
        loggerInfo(check.stdout.trim());
      }
      if (check.stderr.trim().isNotEmpty) {
        loggerWarning(check.stderr.trim());
      }
      if (check.exitCode != 0 && check.exitCode != 2) {
        throw Exception(
          'flutterpatch check-ota 失败 exit=${check.exitCode}'
          '${check.stderr.trim().isEmpty ? '' : ': ${check.stderr.trim()}'}',
        );
      }

      final otaSupported = check.otaSupported && check.exitCode == 0;
      if (resourcesOut.isNotEmpty && !File(resourcesOut).existsSync()) {
        writeHotUpdatableResourcesJson(
          checkJson: check.json,
          path: resourcesOut,
          otaSupported: otaSupported,
        );
        loggerInfo('已写出资源热更配置: $resourcesOut');
      } else if (resourcesOut.isNotEmpty) {
        loggerInfo('已写出资源热更配置: $resourcesOut');
      }

      if (checkOnly) {
        if (otaSupported) {
          loggerSuccess(
            'check-only: 当前工程相对 $releaseVersion 支持热更',
          );
          exitCode = 0;
        } else {
          loggerWarning(
            'check-only: 当前工程相对 $releaseVersion 不支持热更',
          );
          exitCode = 2;
        }
        return;
      }

      if (!otaSupported || check.exitCode == 2) {
        throw Exception(
          '当前工程相对 $releaseVersion 不支持热更（flutterpatch check-ota）。'
          '请重新出包，或加 --force-patch 强行打补丁。',
        );
      }
      loggerSuccess('flutterpatch check-ota 通过，继续打补丁');
    } else {
      loggerWarning('已启用 --force-patch，跳过 flutterpatch check-ota');
    }

    // 可选 bootstrap
    final melos = File(join(appHomeDir.workspace, 'melos.yaml'));
    if (melos.existsSync()) {
      loggerDebug('执行 melos bootstrap...');
      try {
        await ProcessRunner().runProcess(
          ['fvm', 'dart', 'pub', 'run', 'melos', 'bootstrap'],
          workingDirectory: appHomeDir.directory,
          printOutput: true,
        );
      } catch (e) {
        loggerWarning('melos bootstrap 失败，继续尝试 patch: $e');
      }
    }

    final allowAssetDiffs = argResults?['allow-asset-diffs'] == true;
    final whitelistParsed = argResults?.wasParsed('whitelist') == true;
    final uniqueIds = _parseUniqueIds(argResults?['unique-ids']);
    final bool? whitelist;
    if (whitelistParsed) {
      whitelist = argResults?['whitelist'] == true;
    } else if (uniqueIds.isNotEmpty) {
      // 与 flutterpatch 一致：只给 unique-ids 时默认开白名单
      whitelist = true;
    } else {
      whitelist = null;
    }

    final patchNumber = await runFlutterPatchPatch(
      flutterDir: flutterDir,
      platform: flutterPatchPlatform,
      releaseVersion: releaseVersion,
      allowAssetDiffs: allowAssetDiffs,
      whitelist: whitelist,
      uniqueIds: uniqueIds,
    );

    final isUpload = argResults?['isUpload'] as bool? ?? true;
    await cacheAndUploadFlutterPatchArtifacts(
      flutterDir: flutterDir,
      otaPlatform: otaPlatform,
      releaseVersion: releaseVersion,
      isUpload: isUpload,
      sourcePatchNumber: patchNumber,
    );

    loggerSuccess(
      'FlutterPatch 补丁完成: version=$releaseVersion platform=$otaPlatform',
    );
  }

  List<String> _parseUniqueIds(Object? raw) {
    if (raw is! List) return const [];
    final out = <String>[];
    final seen = <String>{};
    for (final item in raw) {
      final id = '$item'.trim();
      if (id.isEmpty || !seen.add(id)) continue;
      out.add(id);
    }
    return out;
  }
}
