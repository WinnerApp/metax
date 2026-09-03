import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:meta_tool/argument_get.dart';
import 'package:meta_tool/commands/patch/patch_compat_gate.dart';
import 'package:meta_tool/common.dart';
import 'package:meta_tool/define.dart';
import 'package:meta_tool/meta_ota.dart';
import 'package:meta_tool/shorebird.dart';
import 'package:path/path.dart';
import 'package:process_runner/process_runner.dart';

abstract class BasePatchCommand extends Command {
  BasePatchCommand() {
    argParser.addOption(
      'release-version',
      help: '宿主版本，如 1.2.3+456，须与当初 Shorebird release 一致',
    );
    argParser.addOption(
      'base-commit',
      help: '热更可行性门禁基线 commit；缺省读 META_OTA_BASE_COMMIT / SHOREBIRD_BASE_COMMIT',
    );
    argParser.addOption(
      'branch',
      help: '切换 Flutter 分支后再打补丁',
    );
    argParser.addOption(
      'channel',
      help: 'Meta OTA promote 渠道，默认 stable',
      defaultsTo: 'stable',
    );
    argParser.addFlag(
      'force-patch',
      help: '跳过 PatchCompatGate（危险，仅排障）',
      defaultsTo: false,
      negatable: false,
    );
    argParser.addFlag(
      'skip-promote',
      help: '只上传 staging，不 promote',
      defaultsTo: false,
      negatable: false,
    );
    argParser.addFlag(
      'useShorebird',
      help: '显式启用 Shorebird（覆盖 yaml）',
      defaultsTo: null,
    );
  }

  String get otaPlatform; // android | ios
  String get shorebirdPlatform; // aar | ios-framework

  @override
  FutureOr<void> run() async {
    final flutterDir = appHomeDir.flutterDir;
    if (!flutterDir.existsSync()) {
      throw Exception('Flutter 目录不存在: ${flutterDir.path}');
    }

    final explicit = argResults?['useShorebird'] as bool?;
    final resolved = resolveUseShorebird(
      appHomeDir: appHomeDir,
      explicitUseShorebird: explicit,
    );
    loggerInfo('Shorebird: enabled=${resolved.enabled} (${resolved.reason})');
    if (!resolved.enabled) {
      throw Exception(
        '当前未启用 Shorebird 热更。请在 pubspec.yaml 设置 metax.shorebird_enabled: true，'
        '或传 --useShorebird / SHOREBIRD_ENABLED=true。',
      );
    }

    final branch = argResults?['branch'] as String?;
    if (branch != null && branch.isNotEmpty) {
      if (skipGitPull) {
        loggerInfo('跳过 Git 操作模式，使用本地代码');
      } else {
        await switchBranch(flutterDir.path, branch);
      }
    }

    final releaseVersion = ArgumentGet(argResults).getString(
      'release-version',
      '请输入 release-version（如 1.2.3+456）',
    );

    final forcePatch = argResults?['force-patch'] == true;
    final baseCommit = (argResults?['base-commit'] as String?)?.trim().isNotEmpty ==
            true
        ? (argResults?['base-commit'] as String).trim()
        : (Platform.environment['META_OTA_BASE_COMMIT'] ??
                Platform.environment['SHOREBIRD_BASE_COMMIT'] ??
                '')
            .trim();

    if (!forcePatch) {
      if (baseCommit.isEmpty) {
        throw Exception(
          '缺少 --base-commit（或 META_OTA_BASE_COMMIT）。'
          '无法做热更可行性门禁时默认中断，避免盲打补丁。'
          '排障可加 --force-patch。',
        );
      }
      await PatchCompatGate(appHomeDir).assertCompatible(baseCommit: baseCommit);
    } else {
      loggerWarning('已启用 --force-patch，跳过 PatchCompatGate');
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

    final patchStarted = DateTime.now();
    await runShorebirdPatch(
      flutterDir: flutterDir,
      platform: shorebirdPlatform,
      releaseVersion: releaseVersion,
    );
    loggerInfo(
      'shorebird_patch elapsed_ms='
      '${DateTime.now().difference(patchStarted).inMilliseconds}',
    );

    final channel = (argResults?['channel'] as String?) ?? 'stable';
    final skipPromote = argResults?['skip-promote'] == true;
    final uploadStarted = DateTime.now();
    final result = await uploadShorebirdPatchToMetaOta(
      appHomeDir: appHomeDir,
      platform: otaPlatform,
      releaseVersion: releaseVersion,
      channel: channel,
      promote: !skipPromote,
    );
    loggerInfo(
      'meta_ota_upload elapsed_ms='
      '${DateTime.now().difference(uploadStarted).inMilliseconds}',
    );

    loggerSuccess(
      '补丁已推送 Meta OTA: patch_id=${result.patchId} '
      'version=$releaseVersion platform=$otaPlatform channel=$channel',
    );
  }
}
