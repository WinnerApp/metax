import 'dart:async';

import 'package:args/command_runner.dart';
import 'package:meta_tool/common.dart';
import 'package:meta_tool/define.dart';
import 'package:meta_tool/doctor.dart';
import 'package:meta_tool/metax_doctor.dart';

/// 打包机全量环境预检。
///
/// ```
/// metax init doctor
/// metax init doctor --platform ios,android --unity --shorebird --patch --upload
/// metax init doctor --skip-network --strict
/// ```
class DoctorCommand extends Command {
  @override
  String get name => 'doctor';

  @override
  String get description =>
      '检测打包机缺少的命令/环境变量/工程配置（覆盖 metax 出包全链路）';

  DoctorCommand() {
    argParser.addMultiOption(
      'platform',
      help: '检查平台（可多选）。默认按工作区已有 ios/android/ohos 目录探测',
      allowed: ['ios', 'android', 'ohos'],
    );
    argParser.addFlag(
      'unity',
      help: '强制检查 Unity / build_winner_app / cmake / UNITY_* 路径',
      defaultsTo: false,
      negatable: false,
    );
    argParser.addFlag(
      'shorebird',
      help: '检查 Shorebird（默认开启；未启用时缺项降为警告）',
      defaultsTo: true,
    );
    argParser.addFlag(
      'patch',
      help: '同时检查补丁链路（meta_ota / Appwrite 构建记录）',
      defaultsTo: false,
      negatable: false,
    );
    argParser.addFlag(
      'upload',
      help: '检查上传凭据（Zealot / Sentry / ASC / Hook / Appwrite）',
      defaultsTo: false,
      negatable: false,
    );
    argParser.addFlag(
      'skip-network',
      help: '跳过 Shorebird 外网连通性 / whoami',
      defaultsTo: false,
      negatable: false,
    );
    argParser.addFlag(
      'strict',
      help: '警告项也视为失败',
      defaultsTo: false,
      negatable: false,
    );
  }

  @override
  FutureOr<void> run() async {
    final platforms = (argResults?['platform'] as List<String>? ?? const [])
        .toSet();
    final options = MetaxDoctorOptions(
      platforms: platforms,
      checkUnity: argResults?['unity'] == true,
      checkShorebird: argResults?['shorebird'] != false,
      checkPatch: argResults?['patch'] == true,
      checkUpload: argResults?['upload'] == true,
      checkNetwork: argResults?['skip-network'] != true,
    );

    loggerInfo('workspace: ${appHomeDir.workspace}');
    loggerInfo(
      '范围: platform=${platforms.isEmpty ? 'auto' : platforms.join(',')} · '
      'unity=${options.checkUnity} · shorebird=${options.checkShorebird} · '
      'patch=${options.checkPatch} · upload=${options.checkUpload} · '
      'network=${options.checkNetwork}',
    );
    loggerInfo('—— metax 环境预检 ——');

    final report = await MetaxDoctor(
      appHomeDir: appHomeDir,
      options: options,
    ).run();

    String? lastGroup;
    for (final item in report.items) {
      if (item.group != null && item.group != lastGroup) {
        lastGroup = item.group;
        loggerInfo('[$lastGroup]');
      }
      _printItem(item);
    }

    final warnCount = report.warnings.length;
    final failCount = report.failures.length;
    final strict = argResults?['strict'] == true;
    loggerInfo(
      '预检汇总: ${report.items.length} 项 · 失败 $failCount · 警告 $warnCount',
    );

    if (failCount > 0 || (strict && warnCount > 0)) {
      final lines = <String>[];
      for (final item in report.failures) {
        lines.add('❌ [${item.group ?? '-'}] ${item.title}: ${item.detail}');
        if (item.fix != null) lines.add('   修复: ${item.fix}');
      }
      if (strict) {
        for (final item in report.warnings) {
          lines.add('⚠️ [${item.group ?? '-'}] ${item.title}: ${item.detail}');
          if (item.fix != null) lines.add('   修复: ${item.fix}');
        }
      }
      throw Exception(
        'metax 环境预检未通过（${failCount + (strict ? warnCount : 0)} 项）。'
        '请先在打包机修好再出包。\n${lines.join('\n')}',
      );
    }

    if (warnCount > 0) {
      loggerWarning('存在 $warnCount 项警告；核心链路可用，请确认是否符合本机构建角色');
    } else {
      loggerSuccess('metax 环境预检通过');
    }

    loggerInfo(
      '提示: 纯 Shorebird 细查可用 `metax init shorebird`；'
      '本机打补丁加 `--patch`，上传机加 `--upload`，Unity 机加 `--unity`',
    );
  }

  void _printItem(DoctorCheckItem item) {
    final tag = item.ok
        ? '✅'
        : (item.severity == DoctorCheckSeverity.error ? '❌' : '⚠️');
    final header = '$tag ${item.title}';
    if (item.ok) {
      loggerSuccess('$header · ${item.detail}');
      return;
    }
    if (item.severity == DoctorCheckSeverity.error) {
      loggerError('$header · ${item.detail}');
    } else {
      loggerWarning('$header · ${item.detail}');
    }
    if (item.fix != null && item.fix!.isNotEmpty) {
      loggerInfo('   修复: ${item.fix}');
    }
  }
}
