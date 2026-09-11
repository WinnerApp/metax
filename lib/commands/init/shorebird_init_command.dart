import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:meta_tool/common.dart';
import 'package:meta_tool/define.dart';
import 'package:meta_tool/doctor.dart';
import 'package:meta_tool/shorebird.dart';
import 'package:meta_tool/shorebird_doctor.dart';
import 'package:path/path.dart';

/// 打包机 Shorebird 环境预检 + 接入提示。
///
/// 用法：
/// ```
/// metax init shorebird
/// metax init shorebird --patch
/// metax init shorebird --skip-network
/// ```
class ShorebirdInitCommand extends Command {
  @override
  String get name => 'shorebird';

  @override
  String get description =>
      '检测打包机 Shorebird 缺什么（CLI/鉴权/网络/工程配置），避免出包末尾才失败';

  ShorebirdInitCommand() {
    argParser.addFlag(
      'writeExample',
      help: '若缺少 shorebird.yaml，写入官方字段示例；并提示 pubspec 开关',
      defaultsTo: false,
      negatable: false,
    );
    argParser.addFlag(
      'patch',
      help: '同时检测补丁链路（meta_ota CLI / META_OTA_API / TOKEN）',
      defaultsTo: false,
      negatable: false,
    );
    argParser.addFlag(
      'skip-network',
      help: '跳过 base_url / download.shorebird.dev 连通性探测',
      defaultsTo: false,
      negatable: false,
    );
    argParser.addFlag(
      'strict',
      help: '警告项也视为失败（默认仅 error 失败）',
      defaultsTo: false,
      negatable: false,
    );
  }

  @override
  FutureOr<void> run() async {
    final flutterDir = appHomeDir.flutterDir;
    final yamlPath = ShorebirdYamlConfig.yamlFile(flutterDir).path;
    final pubspecPath = join(flutterDir.path, 'pubspec.yaml');

    loggerInfo('Flutter 目录: ${flutterDir.path}');
    loggerInfo('shorebird.yaml: $yamlPath');
    loggerInfo('pubspec.yaml: $pubspecPath');

    final yamlFile = File(yamlPath);
    if (!yamlFile.existsSync() && argResults?['writeExample'] == true) {
      await yamlFile.parent.create(recursive: true);
      await yamlFile.writeAsString('''
# 设备 OTA / FlutterPatch 控制面走 base_url（Meta Code Push）
# 启用开关请写在 pubspec.yaml → metax.shorebird_enabled（勿在本文件加自定义 key）
app_id: "00000000-0000-4000-8000-000000000001"
base_url: http://119.23.47.1:9527/
auto_update: true
''');
      loggerSuccess('已写入示例: $yamlPath');
    }

    final checkPatch = argResults?['patch'] == true;
    final skipNetwork = argResults?['skip-network'] == true;
    final strict = argResults?['strict'] == true;

    loggerInfo('—— Shorebird 预检 ——');
    final report = await ShorebirdDoctor(
      appHomeDir: appHomeDir,
      checkPatch: checkPatch,
      checkNetwork: !skipNetwork,
    ).run();

    for (final item in report.items) {
      _printItem(item);
    }

    final warnCount = report.warnings.length;
    final failCount = report.failures.length;
    loggerInfo(
      '预检汇总: ${report.items.length} 项 · '
      '失败 $failCount · 警告 $warnCount',
    );

    if (failCount > 0 || (strict && warnCount > 0)) {
      final lines = <String>[];
      for (final item in report.failures) {
        lines.add('❌ ${item.title}: ${item.detail}');
        if (item.fix != null) lines.add('   修复: ${item.fix}');
      }
      if (strict) {
        for (final item in report.warnings) {
          lines.add('⚠️ ${item.title}: ${item.detail}');
          if (item.fix != null) lines.add('   修复: ${item.fix}');
        }
      }
      throw Exception(
        'Shorebird 预检未通过（${failCount + (strict ? warnCount : 0)} 项）。'
        '请先在打包机修好再出包，避免末尾失败。\n${lines.join('\n')}',
      );
    }

    if (warnCount > 0) {
      loggerWarning('存在 $warnCount 项警告，打包机基本可用，但请确认是否符合预期');
    } else {
      loggerSuccess('Shorebird 预检通过');
    }

    loggerInfo('''
接入清单（app 仓库）:
1. metaapp_flutter/pubspec.yaml 设置:
     metax:
       shorebird_enabled: true
2. metaapp_flutter/shorebird.yaml 仅官方字段 + 可访问的 base_url（勿写 metax_enabled）
3. iOS 嵌入 ShorebirdFlutter.xcframework；Android 改 Shorebird Maven + keepDebugSymbols
4. CI 配置 FLUTTERPATCH_TOKEN；控制面用 shorebird.yaml base_url（勿设 SHOREBIRD_HOSTED_URL）
5. 安装/编译 meta_code_push 的 meta_ota（PATH / META_OTA_BIN / META_CODE_PUSH_ROOT）
6. 出包前全量预检: metax init doctor [--unity] [--patch] [--upload]
   （仅 Shorebird: metax init shorebird [--patch]）
7. 出包: metax upload build_upload_ipa|apk
   （Shorebird release 成功后自动:
     admin upload-release → upload-snapshot → upload-resources）
8. 补丁: metax patch ios|android --release-version X.Y.Z+N
   （shorebird patch 后自动 meta_ota upload，再 upload-resource-pack）
   跳过资源包: --skip-resource-pack 或 META_OTA_SKIP_RESOURCE_PACK=true

模板: templates/shorebird.yaml.example 、 templates/jenkins_shorebird.env.example
''');
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
