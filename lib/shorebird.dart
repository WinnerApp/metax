import 'dart:io';

import 'package:meta_tool/app_home_dir.dart';
import 'package:meta_tool/common.dart';
import 'package:meta_tool/flutter_sdk.dart';
import 'package:path/path.dart';
import 'package:process_runner/process_runner.dart';
import 'package:yaml/yaml.dart';

/// Shorebird / metax 启用解析结果
class ShorebirdResolveResult {
  final bool enabled;
  final String reason;
  final ShorebirdYamlConfig? yaml;

  const ShorebirdResolveResult({
    required this.enabled,
    required this.reason,
    this.yaml,
  });
}

/// `metaapp_flutter/shorebird.yaml` 解析结果（仅 Shorebird 官方字段）。
///
/// **不要**往 shorebird.yaml 写 `metax_enabled`：Shorebird CLI 会校验 key 并报错。
class ShorebirdYamlConfig {
  final String? appId;
  final String? baseUrl;
  final File file;

  const ShorebirdYamlConfig({
    required this.file,
    this.appId,
    this.baseUrl,
  });

  static File yamlFile(Directory flutterDir) =>
      File(join(flutterDir.path, 'shorebird.yaml'));

  static ShorebirdYamlConfig? tryLoad(Directory flutterDir) {
    final file = yamlFile(flutterDir);
    if (!file.existsSync()) {
      return null;
    }
    try {
      final doc = loadYaml(file.readAsStringSync());
      if (doc is! YamlMap) {
        return ShorebirdYamlConfig(file: file);
      }
      return ShorebirdYamlConfig(
        file: file,
        appId: doc['app_id']?.toString(),
        baseUrl: doc['base_url']?.toString(),
      );
    } catch (e) {
      loggerWarning('解析 shorebird.yaml 失败: $e');
      return ShorebirdYamlConfig(file: file);
    }
  }
}

/// 从 `metaapp_flutter/pubspec.yaml` 读取 metax Shorebird 开关。
///
/// 推荐写法：
/// ```yaml
/// metax:
///   shorebird_enabled: true
/// ```
bool? readMetaxShorebirdEnabled(Directory flutterDir) {
  final file = File(join(flutterDir.path, 'pubspec.yaml'));
  if (!file.existsSync()) {
    return null;
  }
  try {
    final doc = loadYaml(file.readAsStringSync());
    if (doc is! YamlMap) {
      return null;
    }
    final metax = doc['metax'];
    if (metax is YamlMap) {
      if (metax.containsKey('shorebird_enabled')) {
        return _asBool(metax['shorebird_enabled']);
      }
      if (metax.containsKey('shorebird')) {
        return _asBool(metax['shorebird']);
      }
    }
    // 兼容顶层（pub 会忽略未知 key）
    if (doc.containsKey('metax_enabled')) {
      return _asBool(doc['metax_enabled']);
    }
  } catch (e) {
    loggerWarning('解析 pubspec.yaml metax 开关失败: $e');
  }
  return null;
}

bool? _asBool(dynamic value) {
  if (value is bool) return value;
  if (value == null) return null;
  final text = value.toString().trim().toLowerCase();
  if (text == 'true' || text == '1' || text == 'yes') return true;
  if (text == 'false' || text == '0' || text == 'no') return false;
  return null;
}

/// 解析是否启用 Shorebird。
///
/// 优先级：CLI 显式 > `SHOREBIRD_ENABLED` > `pubspec.yaml` 的 `metax.shorebird_enabled` > 默认 false。
/// **禁止**仅凭 `shorebird.yaml` 文件是否存在来判断；也**不要**往 shorebird.yaml 写自定义 key。
ShorebirdResolveResult resolveUseShorebird({
  required AppHomeDir appHomeDir,
  bool? explicitUseShorebird,
  Map<String, String>? environment,
}) {
  final env = environment ?? Platform.environment;
  final yaml = ShorebirdYamlConfig.tryLoad(appHomeDir.flutterDir);
  final pubspecEnabled = readMetaxShorebirdEnabled(appHomeDir.flutterDir);

  if (explicitUseShorebird == false) {
    return ShorebirdResolveResult(
      enabled: false,
      reason: 'CLI --no-useShorebird',
      yaml: yaml,
    );
  }
  if (explicitUseShorebird == true) {
    return ShorebirdResolveResult(
      enabled: true,
      reason: 'CLI --useShorebird',
      yaml: yaml,
    );
  }

  final envRaw = (env['SHOREBIRD_ENABLED'] ?? '').trim().toLowerCase();
  if (envRaw == 'true' || envRaw == '1' || envRaw == 'yes') {
    return ShorebirdResolveResult(
      enabled: true,
      reason: 'SHOREBIRD_ENABLED=true',
      yaml: yaml,
    );
  }
  if (envRaw == 'false' || envRaw == '0' || envRaw == 'no') {
    return ShorebirdResolveResult(
      enabled: false,
      reason: 'SHOREBIRD_ENABLED=false',
      yaml: yaml,
    );
  }

  if (pubspecEnabled == true) {
    return ShorebirdResolveResult(
      enabled: true,
      reason: 'pubspec.yaml metax.shorebird_enabled=true',
      yaml: yaml,
    );
  }
  if (pubspecEnabled == false) {
    return ShorebirdResolveResult(
      enabled: false,
      reason: 'pubspec.yaml metax.shorebird_enabled=false',
      yaml: yaml,
    );
  }

  return ShorebirdResolveResult(
    enabled: false,
    reason: 'pubspec.yaml metax.shorebird_enabled unset / default off',
    yaml: yaml,
  );
}

String buildShorebirdReleaseVersion({
  required String buildName,
  required String buildNumber,
}) {
  final name = buildName.trim();
  final number = buildNumber.trim();
  if (name.isEmpty || number.isEmpty) {
    throw ArgumentError('buildName/buildNumber 不能为空');
  }
  if (name.contains('+')) {
    return name;
  }
  return '$name+$number';
}

String? resolveReleaseVersionFromEnv([Map<String, String>? environment]) {
  final env = environment ?? Platform.environment;
  final explicit = (env['SHOREBIRD_RELEASE_VERSION'] ?? '').trim();
  if (explicit.isNotEmpty) return explicit;
  final name = (env['BUILD_VERSION_NAME'] ?? env['BUILD_NAME'] ?? '').trim();
  final number =
      (env['BUILD_VERSION_NUMBER'] ?? env['BUILD_NUMBER'] ?? '').trim();
  if (name.isNotEmpty && number.isNotEmpty) {
    return buildShorebirdReleaseVersion(buildName: name, buildNumber: number);
  }
  return null;
}

String shorebirdFlutterSdkFingerprint(String baseFingerprint) {
  if (baseFingerprint.endsWith('@shorebird')) return baseFingerprint;
  return '$baseFingerprint@shorebird';
}

bool isShorebirdFlutterSdkFingerprint(String fingerprint) {
  return fingerprint.contains('@shorebird');
}

Future<void> ensureShorebirdInstalled() async {
  try {
    final result = await ProcessRunner().runProcess(
      ['which', 'shorebird'],
      printOutput: false,
    );
    if (result.stdout.trim().isEmpty) {
      throw Exception('shorebird not found');
    }
  } catch (_) {
    throw Exception(
      '未找到 shorebird CLI。请安装: '
      'curl --proto "=https" --tlsv1.2 https://raw.githubusercontent.com/shorebirdtech/install/main/install.sh -sSf | bash',
    );
  }
}

/// 解析传给 `--flutter-version` 的版本号（优先 FVM 配置）
String resolveShorebirdFlutterVersion({
  required Directory flutterDir,
  FlutterSdkInfo? sdk,
}) {
  final configured = readConfiguredFvmVersion(flutterDir);
  if (configured != null && configured.isNotEmpty) {
    // FVM 可能是 custom 名；尽量取纯版本号段
    final match = RegExp(r'(\d+\.\d+\.\d+)').firstMatch(configured);
    if (match != null) return match.group(1)!;
    return configured;
  }
  if (sdk != null) {
    final match = RegExp(r'^([^@]+)').firstMatch(sdk.fingerprint);
    if (match != null && match.group(1)!.isNotEmpty) {
      return match.group(1)!;
    }
  }
  throw Exception(
    '无法解析 Shorebird --flutter-version，请在 metaapp_flutter/.fvmrc 配置 Flutter 版本',
  );
}

/// Shorebird CLI 构建/登记用的官方 API。
///
/// 与 `shorebird.yaml` 的 `base_url`（设备 OTA / Meta Code Push）无关。
/// 故意覆盖环境里的 `SHOREBIRD_HOSTED_URL`，避免误把 OTA 地址当成 Console API。
const kShorebirdOfficialHostedUrl = 'https://api.shorebird.dev';

/// Shorebird 打包用的 Flutter 引擎/制品下载源（覆盖国内镜像等误配）。
const kShorebirdFlutterStorageBaseUrl = 'https://download.shorebird.dev';

Map<String, String> shorebirdCliEnvironment([Map<String, String>? base]) {
  final env = Map<String, String>.from(base ?? Platform.environment);
  env['SHOREBIRD_HOSTED_URL'] = kShorebirdOfficialHostedUrl;
  env['FLUTTER_STORAGE_BASE_URL'] = kShorebirdFlutterStorageBaseUrl;
  return env;
}

/// Shorebird 自身选项之后，用 `--` 把参数代理给 flutter。
///
/// 不要传 `--packages=` / `--no-pub`：Shorebird 使用自带 Flutter，会重写
/// `.dart_tool`；`--no-pub` 会阻止其重新 `pub get`，导致
/// `package_config.json does not exist` / monorepo `package_graph` 解析失败。
List<String> _shorebirdFlutterPassthroughArgs(List<String> flutterArgs) {
  return <String>[
    '--',
    ...flutterArgs,
  ];
}

Future<void> runShorebirdRelease({
  required Directory flutterDir,
  required String platform, // ios-framework | aar
  required String releaseVersion,
  required String flutterVersion,
  List<String> extraFlutterArgs = const [],
}) async {
  await ensureShorebirdInstalled();
  final yaml = ShorebirdYamlConfig.tryLoad(flutterDir);
  if (yaml?.appId == null || yaml!.appId!.trim().isEmpty) {
    throw Exception(
      '已启用 Shorebird，但 ${ShorebirdYamlConfig.yamlFile(flutterDir).path} 缺少 app_id',
    );
  }

  final args = <String>[
    'release',
    platform,
    '--release-version',
    releaseVersion,
    '--flutter-version',
    flutterVersion,
    ..._shorebirdFlutterPassthroughArgs(extraFlutterArgs),
  ];

  final cliEnv = shorebirdCliEnvironment();
  loggerInfo(
    '执行: shorebird ${args.join(' ')} '
    '(SHOREBIRD_HOSTED_URL=${cliEnv['SHOREBIRD_HOSTED_URL']}, '
    'FLUTTER_STORAGE_BASE_URL=${cliEnv['FLUTTER_STORAGE_BASE_URL']})',
  );

  await ProcessRunner(environment: cliEnv).runProcess(
    ['shorebird', ...args],
    workingDirectory: flutterDir,
    printOutput: true,
  );
}

Future<void> runShorebirdPatch({
  required Directory flutterDir,
  required String platform, // ios-framework | aar
  required String releaseVersion,
}) async {
  await ensureShorebirdInstalled();
  final args = <String>[
    'patch',
    platform,
    '--release-version',
    releaseVersion,
    ..._shorebirdFlutterPassthroughArgs(const []),
  ];
  loggerInfo('执行: shorebird ${args.join(' ')}');
  await ProcessRunner(environment: shorebirdCliEnvironment()).runProcess(
    ['shorebird', ...args],
    workingDirectory: flutterDir,
    printOutput: true,
  );
}

/// 将 Shorebird iOS release 产物同步到 metax 习惯的 framework 缓存目录
Future<void> syncShorebirdIosReleaseToFrameworkDir(Directory flutterDir) async {
  final releaseDir = Directory(join(flutterDir.path, 'release'));
  final targetDir =
      Directory(join(flutterDir.path, 'build', 'ios', 'framework', 'Release'));
  if (!releaseDir.existsSync()) {
    throw Exception('Shorebird release 目录不存在: ${releaseDir.path}');
  }
  if (targetDir.existsSync()) {
    await targetDir.delete(recursive: true);
  }
  await targetDir.create(recursive: true);
  await copyDirToDir(releaseDir, targetDir);

  // Shorebird 产出 ShorebirdFlutter.xcframework；若仍残留普通 Flutter.xcframework 会混淆
  final flutterXc = Directory(join(targetDir.path, 'Flutter.xcframework'));
  final shorebirdXc =
      Directory(join(targetDir.path, 'ShorebirdFlutter.xcframework'));
  if (shorebirdXc.existsSync() && flutterXc.existsSync()) {
    await flutterXc.delete(recursive: true);
    loggerInfo('已移除旧 Flutter.xcframework，保留 ShorebirdFlutter.xcframework');
  }
  final flutterPodspec = File(join(targetDir.path, 'Flutter.podspec'));
  if (shorebirdXc.existsSync() && flutterPodspec.existsSync()) {
    await flutterPodspec.delete();
    loggerInfo('已移除旧 Flutter.podspec，请使用 ShorebirdFlutter.podspec');
  }

  loggerInfo('已同步 Shorebird iOS 产物到 ${targetDir.path}');
}

/// 将 Shorebird AAR release 产物同步到 flutter build aar 习惯目录
Future<void> syncShorebirdAarReleaseToHostDir(Directory flutterDir) async {
  final releaseDir = Directory(join(flutterDir.path, 'release'));
  final targetDir = Directory(join(flutterDir.path, 'build', 'host'));
  if (!releaseDir.existsSync()) {
    // 部分版本可能直接写到 build/host
    if (targetDir.existsSync()) {
      loggerInfo('使用已有 build/host 作为 AAR 产物目录');
      return;
    }
    throw Exception('Shorebird AAR release 目录不存在: ${releaseDir.path}');
  }
  if (targetDir.existsSync()) {
    await targetDir.delete(recursive: true);
  }
  await targetDir.create(recursive: true);
  await copyDirToDir(releaseDir, targetDir);
  loggerInfo('已同步 Shorebird AAR 产物到 ${targetDir.path}');
}
