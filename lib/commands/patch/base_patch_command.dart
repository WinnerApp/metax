import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:meta_tool/argument_get.dart';
import 'package:meta_tool/commands/patch/patch_compat_gate.dart';
import 'package:meta_tool/commands/patch/patch_release_baseline.dart';
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
      'branch',
      help: 'Melos 分支（与打包一致：切主仓并同步全部子模块后再打补丁）',
    );
    argParser.addOption(
      'channel',
      help: 'Meta OTA promote 渠道（meta_ota upload 目前固定 stable，非 stable 会告警）',
      defaultsTo: 'stable',
    );
    argParser.addFlag(
      'force-patch',
      help: '跳过多仓库热更预审（危险，仅排障/强行热更）',
      defaultsTo: false,
      negatable: false,
    );
    argParser.addFlag(
      'skip-promote',
      help: '只上传 staging，不 promote（meta_ota upload 暂不支持，会告警忽略）',
      defaultsTo: false,
      negatable: false,
    );
    argParser.addFlag(
      'useShorebird',
      help: '显式启用 Shorebird（覆盖 yaml）',
      defaultsTo: null,
    );
    argParser.addFlag(
      'allow-asset-diffs',
      help:
          '透传 shorebird --allow-asset-diffs：允许补丁相对 release 有 asset 差异'
          '（asset 不会打进补丁，仅跳过拦截）',
      defaultsTo: false,
      negatable: false,
    );
    argParser.addFlag(
      'skip-resource-pack',
      help: '跳过 meta_ota upload-resource-pack（不上传变动资源包）',
      defaultsTo: false,
      negatable: false,
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

    String? melosBranch = argResults?['branch'] as String?;
    if (skipGitPull) {
      loggerInfo('跳过 Git 操作模式，使用本地代码');
    } else {
      // 与打包一致：选择 Melos 分支 → 拉最新 → 同步全部子模块到执行分支
      melosBranch = ArgumentGet(argResults).getString(
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

    final forcePatch = argResults?['force-patch'] == true;
    if (!forcePatch) {
      final baselines = await PatchReleaseBaselineResolver(
        appHomeDir: appHomeDir,
        platform: otaPlatform,
      ).resolve(
        releaseVersion: releaseVersion,
        preferMelosBranch: melosBranch,
      );
      await PatchCompatGate(appHomeDir).assertCompatible(baselines);
    } else {
      loggerWarning('已启用 --force-patch，跳过多仓库热更预审');
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
    await runShorebirdPatch(
      flutterDir: flutterDir,
      platform: shorebirdPlatform,
      releaseVersion: releaseVersion,
      allowAssetDiffs: allowAssetDiffs,
    );

    final channel = (argResults?['channel'] as String?) ?? 'stable';
    final skipPromote = argResults?['skip-promote'] == true;
    final result = await uploadShorebirdPatchToMetaOta(
      appHomeDir: appHomeDir,
      platform: otaPlatform,
      releaseVersion: releaseVersion,
      channel: channel,
      promote: !skipPromote,
    );

    loggerSuccess(
      '补丁已由 meta_ota 推送: '
      'patch_id=${result.patchId ?? '(见上方 meta_ota 输出)'} '
      'version=$releaseVersion platform=$otaPlatform channel=$channel',
    );

    await uploadMetaOtaResourcePack(
      appHomeDir: appHomeDir,
      releaseVersion: releaseVersion,
      channel: channel,
      skip: argResults?['skip-resource-pack'] == true,
    );
  }
}
