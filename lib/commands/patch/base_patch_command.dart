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

    final forcePatch = argResults?['force-patch'] == true;
    if (!forcePatch) {
      await ensureGitSafeDirectory(flutterDir.path);
      loggerInfo(
        '热更预检: flutterpatch check-ota version=$releaseVersion '
        'platform=$otaPlatform',
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
      if (!check.otaSupported || check.exitCode == 2) {
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
    await runFlutterPatchPatch(
      flutterDir: flutterDir,
      platform: flutterPatchPlatform,
      releaseVersion: releaseVersion,
      allowAssetDiffs: allowAssetDiffs,
    );

    final isUpload = argResults?['isUpload'] as bool? ?? true;
    await cacheAndUploadFlutterPatchArtifacts(
      flutterDir: flutterDir,
      otaPlatform: otaPlatform,
      releaseVersion: releaseVersion,
      isUpload: isUpload,
    );

    loggerSuccess(
      'FlutterPatch 补丁完成: version=$releaseVersion platform=$otaPlatform',
    );
  }
}
