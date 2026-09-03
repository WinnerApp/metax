import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:meta_tool/common.dart';
import 'package:meta_tool/define.dart';
import 'package:meta_tool/shorebird.dart';
import 'package:path/path.dart';

/// 打印 / 写入 Shorebird + Meta OTA 接入说明（不改宿主工程）
class ShorebirdInitCommand extends Command {
  @override
  String get name => 'shorebird';

  @override
  String get description =>
      '检查/提示 Shorebird 与 Meta OTA 配置（pubspec metax.shorebird_enabled）';

  ShorebirdInitCommand() {
    argParser.addFlag(
      'writeExample',
      help: '若缺少 shorebird.yaml，写入官方字段示例；并提示 pubspec 开关',
      defaultsTo: false,
      negatable: false,
    );
  }

  @override
  FutureOr<void> run() async {
    final flutterDir = appHomeDir.flutterDir;
    final yamlPath = ShorebirdYamlConfig.yamlFile(flutterDir).path;
    final pubspecPath = join(flutterDir.path, 'pubspec.yaml');
    final resolved = resolveUseShorebird(appHomeDir: appHomeDir);
    final pubspecEnabled = readMetaxShorebirdEnabled(flutterDir);

    loggerInfo('Flutter 目录: ${flutterDir.path}');
    loggerInfo('shorebird.yaml: $yamlPath');
    loggerInfo('pubspec.yaml: $pubspecPath');
    loggerInfo('解析结果: enabled=${resolved.enabled} (${resolved.reason})');
    loggerInfo('  metax.shorebird_enabled: $pubspecEnabled');
    if (resolved.yaml != null) {
      loggerInfo('  app_id: ${resolved.yaml!.appId}');
      loggerInfo('  base_url: ${resolved.yaml!.baseUrl}');
    }

    final yamlFile = File(yamlPath);
    if (!yamlFile.existsSync() && argResults?['writeExample'] == true) {
      await yamlFile.parent.create(recursive: true);
      await yamlFile.writeAsString('''
# 设备 OTA 走 Meta Code Push（base_url），不是 api.shorebird.dev
# 启用开关请写在 pubspec.yaml → metax.shorebird_enabled（勿在本文件加自定义 key）
app_id: "00000000-0000-4000-8000-000000000001"
base_url: http://119.23.47.1:9527/
auto_update: true
''');
      loggerSuccess('已写入示例: $yamlPath');
    }

    loggerInfo('''
接入清单（app 仓库）:
1. metaapp_flutter/pubspec.yaml 设置:
     metax:
       shorebird_enabled: true
2. metaapp_flutter/shorebird.yaml 仅官方字段 + 可访问的 base_url（勿写 metax_enabled）
3. iOS 嵌入 ShorebirdFlutter.xcframework；Android 改 Shorebird Maven + keepDebugSymbols
4. CI 配置 SHOREBIRD_TOKEN、META_OTA_API=http://119.23.47.1:9527/ 、META_OTA_TOKEN
   （CLI 登记由 metax 强制 SHOREBIRD_HOSTED_URL=https://api.shorebird.dev，勿把 OTA 地址赋给它）
5. 出包: metax upload build_upload_ipa|apk（IPA/APK 仍走 fastlane）
6. 补丁: metax patch ios|android --release-version X.Y.Z+N --base-commit <release_flutter_sha>

模板: templates/shorebird.yaml.example 、 templates/jenkins_shorebird.env.example
''');
  }
}
