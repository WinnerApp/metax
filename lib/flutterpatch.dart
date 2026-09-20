import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:meta_tool/app_home_dir.dart';
import 'package:meta_tool/cache/cache_model.dart';
import 'package:meta_tool/common.dart';
import 'package:meta_tool/define.dart';
import 'package:meta_tool/estimated_progress.dart';
import 'package:meta_tool/flutter_sdk.dart';
import 'package:path/path.dart';
import 'package:process_runner/process_runner.dart';
import 'package:yaml/yaml.dart';

/// Written into framework/aar zip so Appwrite download can restore provenance
/// even when the cloud document lacks `contentHash` attributes.
const kMetaxArtifactSidecarFileName = '.metax_artifact.json';

/// FlutterPatch / metax 启用解析结果
class FlutterPatchResolveResult {
  final bool enabled;
  final String reason;
  final FlutterPatchYamlConfig? yaml;

  const FlutterPatchResolveResult({
    required this.enabled,
    required this.reason,
    this.yaml,
  });
}

/// `metaapp_flutter/shorebird.yaml` 解析结果（仅 FlutterPatch 官方字段）。
///
/// **不要**往 shorebird.yaml 写 `metax_enabled`：FlutterPatch CLI 会校验 key 并报错。
class FlutterPatchYamlConfig {
  final String? appId;
  final String? baseUrl;
  final File file;

  const FlutterPatchYamlConfig({
    required this.file,
    this.appId,
    this.baseUrl,
  });

  static File yamlFile(Directory flutterDir) =>
      File(join(flutterDir.path, 'shorebird.yaml'));

  static FlutterPatchYamlConfig? tryLoad(Directory flutterDir) {
    final file = yamlFile(flutterDir);
    if (!file.existsSync()) {
      return null;
    }
    try {
      final doc = loadYaml(file.readAsStringSync());
      if (doc is! YamlMap) {
        return FlutterPatchYamlConfig(file: file);
      }
      return FlutterPatchYamlConfig(
        file: file,
        appId: doc['app_id']?.toString(),
        baseUrl: doc['base_url']?.toString(),
      );
    } catch (e) {
      loggerWarning('解析 shorebird.yaml 失败: $e');
      return FlutterPatchYamlConfig(file: file);
    }
  }
}

/// 从 `metaapp_flutter/pubspec.yaml` 读取 metax FlutterPatch 开关。
///
/// 写法：
/// ```yaml
/// metax:
///   shorebird_enabled: true
/// ```
bool? readMetaxFlutterPatchEnabled(Directory flutterDir) {
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

/// 解析是否启用 FlutterPatch。
///
/// 优先级：CLI 显式 > `FLUTTERPATCH_ENABLED`（兼容 `SHOREBIRD_ENABLED`）>
/// `pubspec.yaml` 的 `metax.shorebird_enabled` > 默认 false。
/// **禁止**仅凭 `shorebird.yaml` 文件是否存在来判断；也**不要**往 shorebird.yaml 写自定义 key。
FlutterPatchResolveResult resolveUseFlutterPatch({
  required AppHomeDir appHomeDir,
  bool? explicitUseFlutterPatch,
  Map<String, String>? environment,
}) {
  final env = environment ?? Platform.environment;
  final yaml = FlutterPatchYamlConfig.tryLoad(appHomeDir.flutterDir);
  final pubspecEnabled = readMetaxFlutterPatchEnabled(appHomeDir.flutterDir);

  if (explicitUseFlutterPatch == false) {
    return FlutterPatchResolveResult(
      enabled: false,
      reason: 'CLI --no-useFlutterPatch',
      yaml: yaml,
    );
  }
  if (explicitUseFlutterPatch == true) {
    return FlutterPatchResolveResult(
      enabled: true,
      reason: 'CLI --useFlutterPatch',
      yaml: yaml,
    );
  }

  final envKey = env.containsKey('FLUTTERPATCH_ENABLED')
      ? 'FLUTTERPATCH_ENABLED'
      : (env.containsKey('SHOREBIRD_ENABLED') ? 'SHOREBIRD_ENABLED' : null);
  final envRaw =
      envKey == null ? '' : (env[envKey] ?? '').trim().toLowerCase();
  if (envRaw == 'true' || envRaw == '1' || envRaw == 'yes') {
    return FlutterPatchResolveResult(
      enabled: true,
      reason: '$envKey=true',
      yaml: yaml,
    );
  }
  if (envRaw == 'false' || envRaw == '0' || envRaw == 'no') {
    return FlutterPatchResolveResult(
      enabled: false,
      reason: '$envKey=false',
      yaml: yaml,
    );
  }

  if (pubspecEnabled == true) {
    return FlutterPatchResolveResult(
      enabled: true,
      reason: 'pubspec.yaml metax.shorebird_enabled=true',
      yaml: yaml,
    );
  }
  if (pubspecEnabled == false) {
    return FlutterPatchResolveResult(
      enabled: false,
      reason: 'pubspec.yaml metax.shorebird_enabled=false',
      yaml: yaml,
    );
  }

  return FlutterPatchResolveResult(
    enabled: false,
    reason: 'pubspec.yaml metax.shorebird_enabled unset / default off',
    yaml: yaml,
  );
}

String buildFlutterPatchReleaseVersion({
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

/// 解析 `1.2.3+456` → (buildName, buildNumber)。
({String buildName, String buildNumber}) parseFlutterPatchReleaseVersion(
  String releaseVersion,
) {
  final raw = releaseVersion.trim();
  final plus = raw.lastIndexOf('+');
  if (plus <= 0 || plus >= raw.length - 1) {
    throw ArgumentError(
      'release-version 格式应为 buildName+buildNumber，例如 1.2.3+456，收到: $releaseVersion',
    );
  }
  final buildName = raw.substring(0, plus).trim();
  final buildNumber = raw.substring(plus + 1).trim();
  if (buildName.isEmpty || buildNumber.isEmpty) {
    throw ArgumentError(
      'release-version 格式应为 buildName+buildNumber，例如 1.2.3+456，收到: $releaseVersion',
    );
  }
  return (buildName: buildName, buildNumber: buildNumber);
}

String? resolveReleaseVersionFromEnv([Map<String, String>? environment]) {
  final env = environment ?? Platform.environment;
  final explicit = (env['FLUTTERPATCH_RELEASE_VERSION'] ??
          env['SHOREBIRD_RELEASE_VERSION'] ??
          '')
      .trim();
  if (explicit.isNotEmpty) return explicit;
  final name = (env['BUILD_VERSION_NAME'] ?? env['BUILD_NAME'] ?? '').trim();
  final number =
      (env['BUILD_VERSION_NUMBER'] ?? env['BUILD_NUMBER'] ?? '').trim();
  if (name.isNotEmpty && number.isNotEmpty) {
    return buildFlutterPatchReleaseVersion(buildName: name, buildNumber: number);
  }
  return null;
}

String shorebirdSdkFingerprint(String baseFingerprint) {
  if (baseFingerprint.endsWith('@shorebird') ||
      baseFingerprint.endsWith('@flutterpatch')) {
    return baseFingerprint;
  }
  return '$baseFingerprint@shorebird';
}

bool isShorebirdSdkFingerprint(String fingerprint) {
  return fingerprint.contains('@shorebird') ||
      fingerprint.contains('@flutterpatch');
}

/// 判断缓存条目是否为 FlutterPatch 产物。
///
/// 优先看显式字段 [CacheModel.isShorebird]；旧缓存无该字段时回退到
/// `flutterSdk` 指纹中的 `@shorebird` 标记。
bool cacheEntryIsShorebird({
  required bool isShorebird,
  required String flutterSdk,
}) {
  if (isShorebird) return true;
  return isShorebirdSdkFingerprint(flutterSdk);
}

/// FlutterPatch CLI 可执行名（品牌入口）。
const kFlutterPatchCliName = 'flutterpatch';

/// 解析 FlutterPatch CLI：`FLUTTERPATCH_BIN` > PATH 中的 `flutterpatch`。
String resolveFlutterPatchCli([Map<String, String>? environment]) {
  final env = environment ?? Platform.environment;
  final fromBin = (env['FLUTTERPATCH_BIN'] ?? '').trim();
  if (fromBin.isNotEmpty) return fromBin;
  return kFlutterPatchCliName;
}

/// 组装 `flutterpatch check-ota` 参数（不含可执行文件名）。
///
/// `--json` 放在子命令前，与 FlutterPatch 全局选项一致。
List<String> buildFlutterPatchCheckOtaArgs({
  required String flutterDir,
  required String platform,
  required String releaseVersion,
  String? androidDir,
  String? iosDir,
  String? unsupportedOut,
  String? supportedOut,
  String? resourcesOut,
  bool json = true,
}) {
  return <String>[
    if (json) '--json',
    'check-ota',
    '--flutter',
    flutterDir,
    '--platform',
    platform,
    '--version',
    releaseVersion,
    '--no-write',
    if (unsupportedOut != null && unsupportedOut.trim().isNotEmpty) ...[
      '--unsupported-out',
      unsupportedOut.trim(),
    ],
    if (supportedOut != null && supportedOut.trim().isNotEmpty) ...[
      '--supported-out',
      supportedOut.trim(),
    ],
    if (resourcesOut != null && resourcesOut.trim().isNotEmpty) ...[
      '--resources-out',
      resourcesOut.trim(),
    ],
    if (platform == 'android' &&
        androidDir != null &&
        androidDir.trim().isNotEmpty) ...[
      '--android',
      androidDir.trim(),
    ],
    if (platform == 'ios' && iosDir != null && iosDir.trim().isNotEmpty) ...[
      '--ios',
      iosDir.trim(),
    ],
  ];
}

/// Unwrap FlutterPatch `--json` envelope `{status, data, meta}` → `data`.
///
/// Older CLIs / tests may emit a flat check-ota payload; those pass through.
Map<String, dynamic>? unwrapFlutterPatchJson(Map<String, dynamic>? raw) {
  if (raw == null) return null;
  final data = raw['data'];
  if (raw.containsKey('status') && data is Map) {
    return Map<String, dynamic>.from(data);
  }
  return raw;
}

/// 从 check-ota JSON 写出资源热更配置：
/// 全量清单 + 增量变动 + 不支持热更的变动。
///
/// 即使列表为空也会写文件，便于 Jenkins 产物归档。
/// 优先使用 CLI `--resources-out`；本函数仅作旧版 CLI 的回退。
void writeHotUpdatableResourcesJson({
  required Map<String, dynamic>? checkJson,
  required String path,
  bool? otaSupported,
}) {
  final trimmed = path.trim();
  if (trimmed.isEmpty) return;

  final payloadIn = unwrapFlutterPatchJson(checkJson);
  final resourcesRaw = payloadIn?['resources'];
  final resources = resourcesRaw is List ? resourcesRaw : const [];
  final assetChangesRaw = payloadIn?['asset_changes'];
  final assetChanges = assetChangesRaw is List ? assetChangesRaw : const [];
  final unsupportedRaw = payloadIn?['unsupported_asset_changes'];
  final unsupportedList = unsupportedRaw is List ? unsupportedRaw : const [];

  final payload = <String, dynamic>{
    'ota_supported': otaSupported ?? payloadIn?['ota_supported'] == true,
    'resource_count': resources.length,
    // 当前工程全量 Flutter asset 清单（非 diff）
    'resources': resources,
    'asset_change_count': assetChanges.length,
    // 相对服务端资源基线的增量（add/update/remove，可热更）
    'asset_changes': assetChanges,
    'unsupported_asset_change_count': unsupportedList.length,
    // 命中 .flutterpatch-unsupported-resources，变了需整包发版
    'unsupported_asset_changes': unsupportedList,
  };
  final file = File(trimmed);
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(payload)}\n',
  );
}

/// 组装 `flutterpatch patch` 参数（不含可执行文件名）。
List<String> buildFlutterPatchPatchArgs({
  required String platform,
  required String releaseVersion,
  bool allowAssetDiffs = false,
  bool? whitelist,
  List<String> uniqueIds = const [],
}) {
  final ids = <String>[];
  final seen = <String>{};
  for (final raw in uniqueIds) {
    final id = raw.trim();
    if (id.isEmpty || !seen.add(id)) continue;
    ids.add(id);
  }
  return <String>[
    'patch',
    platform,
    '--release-version',
    releaseVersion,
    if (allowAssetDiffs) '--allow-asset-diffs',
    if (whitelist == true) '--whitelist',
    if (whitelist == false) '--no-whitelist',
    if (ids.isNotEmpty) ...['--unique-ids', ids.join(',')],
    ..._flutterPatchFlutterPassthroughArgs(const []),
  ];
}

class FlutterPatchCheckOtaResult {
  final int exitCode;
  final bool otaSupported;
  final Map<String, dynamic>? json;
  final String stdout;
  final String stderr;

  const FlutterPatchCheckOtaResult({
    required this.exitCode,
    required this.otaSupported,
    required this.json,
    required this.stdout,
    required this.stderr,
  });
}

Map<String, dynamic>? parseLastJsonObject(String text) {
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

/// 调用 `flutterpatch check-ota`：对照服务端 snapshot 判断当前 Flutter 工程是否可热更。
///
/// 退出码与 CLI 对齐：0 支持 / 2 不支持；其它为执行失败。
Future<FlutterPatchCheckOtaResult> runFlutterPatchCheckOta({
  required Directory flutterDir,
  required String platform,
  required String releaseVersion,
  Directory? androidDir,
  Directory? iosDir,
  String? unsupportedOut,
  String? supportedOut,
  String? resourcesOut,
}) async {
  await ensureFlutterPatchInstalled();
  final cli = resolveFlutterPatchCli();
  final args = buildFlutterPatchCheckOtaArgs(
    flutterDir: flutterDir.path,
    platform: platform,
    releaseVersion: releaseVersion,
    androidDir: androidDir?.path,
    iosDir: iosDir?.path,
    unsupportedOut: unsupportedOut,
    supportedOut: supportedOut,
    resourcesOut: resourcesOut,
  );
  loggerInfo('执行: $cli ${args.join(' ')}');
  final result = await ProcessRunner(
    environment: flutterPatchCliEnvironment(),
  ).runProcess(
    [cli, ...args],
    workingDirectory: flutterDir,
    printOutput: false,
    failOk: true,
  );
  final stdoutText = result.stdout.toString();
  final stderrText = result.stderr.toString();
  final raw = parseLastJsonObject(stdoutText) ?? parseLastJsonObject(stderrText);
  // FlutterPatch `--json` wraps payloads as {status, data, meta}.
  final json = unwrapFlutterPatchJson(raw);
  final otaSupported = json?['ota_supported'] == true ||
      (json?['ota_supported'] == null && result.exitCode == 0);
  return FlutterPatchCheckOtaResult(
    exitCode: result.exitCode,
    otaSupported: otaSupported && result.exitCode != 2,
    json: json,
    stdout: stdoutText,
    stderr: stderrText,
  );
}

Future<void> ensureFlutterPatchInstalled([Map<String, String>? environment]) async {
  final cli = resolveFlutterPatchCli(environment);
  if (cli.contains(Platform.pathSeparator) || cli.startsWith('.')) {
    if (!File(cli).existsSync()) {
      throw Exception(
        '未找到 FlutterPatch CLI: $cli\n'
        '请设置 FLUTTERPATCH_BIN 或安装 flutterpatch（~/.flutterpatch/bin）',
      );
    }
    return;
  }
  try {
    final result = await ProcessRunner().runProcess(
      ['which', cli],
      printOutput: false,
    );
    if (result.stdout.trim().isEmpty) {
      throw Exception('$cli not found');
    }
  } catch (_) {
    throw Exception(
      '未找到 FlutterPatch CLI（$cli）。\n'
      '安装到 ~/.flutterpatch/bin 并加入 PATH，或设置 FLUTTERPATCH_BIN。\n'
      '见 flutterpatch 官网 downloads/install_cli.sh',
    );
  }
}

/// 解析传给 `--flutter-version` 的版本号（优先 FVM 配置，向上查找 melos 根 `.fvmrc`）
String resolveFlutterPatchVersion({
  required Directory flutterDir,
  FlutterSdkInfo? sdk,
  Directory? workspaceDir,
}) {
  final configured = readConfiguredFvmVersion(
    flutterDir,
    stopAt: workspaceDir,
  );
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
    '无法解析 FlutterPatch --flutter-version。'
    '请在 melos 仓库根或 metaapp_flutter 配置 .fvmrc（fvm use x.y.z）',
  );
}

/// FlutterPatch 打包用的 Flutter 引擎/制品下载源（覆盖国内镜像等误配）。
const kFlutterPatchStorageBaseUrl = 'https://download.shorebird.dev';

/// FlutterPatch CLI 运行环境。
///
/// 控制面地址只读 `shorebird.yaml` → `base_url`；会移除误配的
/// `SHOREBIRD_HOSTED_URL`。引擎 CDN 固定为 FlutterPatch download，避免国内镜像缺制品。
Map<String, String> flutterPatchCliEnvironment([Map<String, String>? base]) {
  final env = Map<String, String>.from(base ?? Platform.environment);
  env.remove('SHOREBIRD_HOSTED_URL');
  env['FLUTTER_STORAGE_BASE_URL'] = kFlutterPatchStorageBaseUrl;
  return env;
}

/// FlutterPatch 自身选项之后，用 `--` 把参数代理给 flutter。
///
/// 不要传 `--packages=` / `--no-pub`：FlutterPatch 使用自带 Flutter，会重写
/// `.dart_tool`；`--no-pub` 会阻止其重新 `pub get`，导致
/// `package_config.json does not exist` / monorepo `package_graph` 解析失败。
///
/// 不要在透传参数里传 `--target-platform`：FlutterPatch 会按自身
/// `--target-platform`（默认三 ABI）再拼进 `flutter build aar`；若透传再带
/// 一次，MultiOption 会合并出重复 ABI，触发
/// `packJniLibsflutterBuildRelease` 的 `libapp.so is a duplicate`。
/// ABI 限制请放进 [extraFlutterPatchArgs]。
///
/// release / patch 都强制 `--no-tree-shake-icons`，避免 MaterialIcons /
/// tdesign 等图标字体因树摇子集不一致触发 asset diff。
List<String> _flutterPatchFlutterPassthroughArgs(List<String> flutterArgs) {
  final args = List<String>.of(flutterArgs).where((arg) {
    return !arg.startsWith('--target-platform');
  }).toList();
  if (!args.contains('--no-tree-shake-icons')) {
    args.add('--no-tree-shake-icons');
  }
  return <String>[
    '--',
    ...args,
  ];
}

Future<void> runFlutterPatchRelease({
  required Directory flutterDir,
  required String platform, // ios-framework | aar
  required String releaseVersion,
  required String flutterVersion,
  List<String> extraFlutterArgs = const [],
  /// FlutterPatch CLI 自身参数（写在 `--` 前），例如 `--target-platform=android-arm64`。
  List<String> extraFlutterPatchArgs = const [],
  /// 从已有 release clone 产物登记新宿主版本（不重编 Flutter）。
  /// 与 [flutterVersion] / 透传 build 参数互斥使用。
  String? fromRelease,
  /// 与 `--from-release` 联用：按全量二进制 hash 解析 OTA 基线（硬失败）。
  String? artifactHash,
  /// 与 `--from-release` 联用：从指定 patch 全量基线 clone。
  int? sourcePatchNumber,
}) async {
  await ensureFlutterPatchInstalled();
  final yaml = FlutterPatchYamlConfig.tryLoad(flutterDir);
  if (yaml?.appId == null || yaml!.appId!.trim().isEmpty) {
    throw Exception(
      '已启用 FlutterPatch，但 ${FlutterPatchYamlConfig.yamlFile(flutterDir).path} 缺少 app_id',
    );
  }

  final cli = resolveFlutterPatchCli();
  final cliEnv = flutterPatchCliEnvironment();
  final from = fromRelease?.trim() ?? '';
  final List<String> args;
  if (from.isNotEmpty) {
    if (from == releaseVersion.trim()) {
      throw Exception(
        '--from-release 不能与 --release-version 相同 ($releaseVersion)',
      );
    }
    // clone 路径不重编，不清 release/，不传 --flutter-version
    args = <String>[
      'release',
      platform,
      '--release-version',
      releaseVersion,
      '--from-release',
      from,
      if (artifactHash != null && artifactHash.trim().isNotEmpty) ...[
        '--artifact-hash',
        artifactHash.trim(),
      ],
      if (sourcePatchNumber != null) ...[
        '--source-patch-number',
        '$sourcePatchNumber',
      ],
    ];
  } else {
    // iOS / Android 共用 flutter/release；不清空会把上一平台残留打进下一平台缓存。
    await clearFlutterPatchReleaseDir(flutterDir);
    args = <String>[
      'release',
      platform,
      '--release-version',
      releaseVersion,
      '--flutter-version',
      flutterVersion,
      ...extraFlutterPatchArgs,
      ..._flutterPatchFlutterPassthroughArgs(extraFlutterArgs),
    ];
  }

  loggerInfo(
    '执行: $cli ${args.join(' ')} '
    '(FLUTTER_STORAGE_BASE_URL=${cliEnv['FLUTTER_STORAGE_BASE_URL']})',
  );

  final sw = Stopwatch()..start();
  try {
    await ProcessRunner(environment: cliEnv).runProcess(
      [cli, ...args],
      workingDirectory: flutterDir,
      printOutput: true,
    );
    loggerInfo(
      'shell 完成: $cli ${args.take(2).join(' ')} · '
      '用时 ${formatElapsedDuration(sw.elapsed)}',
    );
  } catch (e) {
    loggerInfo(
      'shell 失败: $cli ${args.take(2).join(' ')} · '
      '用时 ${formatElapsedDuration(sw.elapsed)}',
    );
    rethrow;
  }
}

/// framework/aar 缓存命中后：若宿主版本变了，按 **contentHash → 控制面 by-hash**
/// 判定基线身份，再 `--from-release`。
///
/// 本地不区分 release / 补丁槽：同一 zip 槽可放任一种全量包。
/// - by-hash `origin=release` → clone release 基线
/// - by-hash `origin=patch` → 带 `--source-patch-number` promote 补丁基线
///
/// [sourcePatchNumber] / [artifactKind] 仅作可选一致性校验，不参与路径选择。
/// hash / origin / version 不一致一律抛错（硬失败）。
Future<bool> maybeCloneFlutterPatchReleaseFromCache({
  required Directory flutterDir,
  required String platform, // ios-framework | aar
  required String releaseVersion,
  required String? cachedReleaseVersion,
  CacheArtifactKind artifactKind = CacheArtifactKind.release,
  String? contentHash,
  int? sourcePatchNumber,
}) async {
  final current = releaseVersion.trim();
  final from = (cachedReleaseVersion ?? '').trim();
  if (current.isEmpty) {
    return false;
  }
  if (from.isEmpty) {
    loggerWarning(
      'FlutterPatch 缓存命中，但未记录 releaseVersion，'
      '无法执行 --from-release 登记 $current。'
      '下次完整编译后会写入该字段；或对本库 --forceUpdate / 关 Flutter 缓存重编。',
    );
    return false;
  }
  if (from == current) {
    loggerInfo(
      'FlutterPatch 缓存 releaseVersion 已是当前打包版本 $current，跳过 --from-release',
    );
    return false;
  }

  final hash = (contentHash ?? '').trim();
  if (hash.isEmpty) {
    loggerWarning(
      'FlutterPatch 缓存缺少 contentHash，无法 by-hash 判定 release/patch；'
      '仍将尝试 --from-release（建议重新 release/patch 一次以写入哈希）。',
    );
    loggerInfo(
      'FlutterPatch 缓存命中：clone $from → $current（无 hash，跳过 Flutter 重编）',
    );
    await runFlutterPatchRelease(
      flutterDir: flutterDir,
      platform: platform,
      releaseVersion: current,
      flutterVersion: '',
      fromRelease: from,
    );
    return true;
  }

  final provenance = await _resolveFlutterPatchBaselineByHash(
    flutterDir: flutterDir,
    artifactHash: hash,
    expectedReleaseVersion: from,
    localSourcePatchNumber: sourcePatchNumber,
  );

  final promoteFromPatch = provenance.origin == 'patch';
  final patchNo = provenance.patchNumber;
  if (promoteFromPatch && patchNo == null) {
    throw Exception(
      'by-hash 显示 origin=patch，但缺少 patch_number；'
      '请重新 patch 一次后再 promote。',
    );
  }

  loggerInfo(
    promoteFromPatch
        ? 'FlutterPatch 缓存 by-hash：origin=patch #$patchNo，'
            'clone $from → $current'
        : 'FlutterPatch 缓存 by-hash：origin=release，'
            'clone $from → $current（跳过 Flutter 重编）',
  );
  await runFlutterPatchRelease(
    flutterDir: flutterDir,
    platform: platform,
    releaseVersion: current,
    flutterVersion: '', // clone 路径不使用
    fromRelease: from,
    artifactHash: hash,
    sourcePatchNumber: promoteFromPatch ? patchNo : null,
  );
  return true;
}

/// Resolved baseline provenance from by-hash.
typedef _BaselineProvenance = ({String origin, int? patchNumber});

/// GET /admin/v1/baselines/by-artifact-hash：用二进制 hash 判定 origin，
/// 不依赖本地 release/patch 标签。
Future<_BaselineProvenance> _resolveFlutterPatchBaselineByHash({
  required Directory flutterDir,
  required String artifactHash,
  required String expectedReleaseVersion,
  int? localSourcePatchNumber,
}) async {
  final hash = artifactHash.trim();
  if (hash.isEmpty) {
    throw ArgumentError.value(artifactHash, 'artifactHash', 'must be non-empty');
  }

  final body = await lookupFlutterPatchBaselinesByArtifactHash(
    flutterDir: flutterDir,
    artifactHash: hash,
  );
  if (body == null) {
    throw Exception(
      '控制面未找到 artifact_hash=$hash 的 OTA 基线（by-hash 404）。'
      '请确认 release/patch 已上传带 provenance 的全量基线。',
    );
  }

  Map<String, dynamic>? row;
  final resource = body['resource'];
  final snapshot = body['snapshot'];
  final package = body['package'];
  if (resource is Map) {
    row = Map<String, dynamic>.from(resource);
  } else if (snapshot is Map) {
    row = Map<String, dynamic>.from(snapshot);
  }
  if (row == null) {
    throw Exception('by-hash 响应缺少 resource/snapshot 行');
  }

  final origin = '${row['origin'] ?? 'release'}'.trim().toLowerCase();
  final version = '${row['release_version'] ?? ''}'.trim();
  final patch = (row['patch_number'] as num?)?.toInt();

  if (version.isNotEmpty && version != expectedReleaseVersion) {
    throw Exception(
      '基线 release_version=$version，与缓存记录 $expectedReleaseVersion 不一致',
    );
  }

  if (origin != 'release' && origin != 'patch') {
    throw Exception(
      'by-hash 未知 origin=$origin'
      '${patch != null ? ' patch=#$patch' : ''}',
    );
  }

  if (origin == 'patch') {
    if (hash.isNotEmpty && package is! Map) {
      throw Exception(
        'by-hash 未找到补丁全量包产物（package）。'
        '请用已上传完整 aar/xcframework 的 flutterpatch 重新打补丁后再 promote。',
      );
    }
    if (localSourcePatchNumber != null &&
        patch != null &&
        localSourcePatchNumber != patch) {
      throw Exception(
        '本地 sourcePatchNumber=#$localSourcePatchNumber '
        '与 by-hash patch=#$patch 不一致',
      );
    }
  } else if (localSourcePatchNumber != null) {
    loggerWarning(
      '本地记有 sourcePatchNumber=#$localSourcePatchNumber，'
      '但 by-hash origin=release；以控制面 hash 为准。',
    );
  }

  return (origin: origin, patchNumber: patch);
}

/// Looks up baselines by full binary hash on the control plane.
///
/// Returns null on 404. Throws on auth / other errors.
Future<Map<String, dynamic>?> lookupFlutterPatchBaselinesByArtifactHash({
  required Directory flutterDir,
  required String artifactHash,
  String? appId,
}) async {
  final hash = artifactHash.trim();
  if (hash.isEmpty) {
    throw ArgumentError.value(artifactHash, 'artifactHash', 'must be non-empty');
  }
  final yaml = FlutterPatchYamlConfig.tryLoad(flutterDir);
  final baseUrl = (yaml?.baseUrl ?? '').trim();
  if (baseUrl.isEmpty) {
    throw Exception(
      'shorebird.yaml 缺少 base_url，无法 by-hash 查询 OTA 基线',
    );
  }
  final resolvedAppId = (appId ?? yaml?.appId ?? '').trim();
  final token = (Platform.environment['FLUTTERPATCH_TOKEN'] ?? '').trim();
  if (token.isEmpty) {
    throw Exception('未设置 FLUTTERPATCH_TOKEN，无法 by-hash 查询 OTA 基线');
  }

  final uri = Uri.parse(baseUrl).replace(
    path: _joinUrlPath(Uri.parse(baseUrl).path, '/admin/v1/baselines/by-artifact-hash'),
    queryParameters: {
      'hash': hash,
      if (resolvedAppId.isNotEmpty) 'app_id': resolvedAppId,
    },
  );
  final response = await http.get(
    uri,
    headers: {
      'authorization': 'Bearer $token',
      'accept': 'application/json',
    },
  );
  if (response.statusCode == 404) return null;
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw Exception(
      'by-hash 查询失败 HTTP ${response.statusCode}: ${response.body}',
    );
  }
  final decoded = jsonDecode(response.body);
  if (decoded is! Map) {
    throw Exception('by-hash 响应不是 JSON object');
  }
  return decoded.cast<String, dynamic>();
}

String _joinUrlPath(String basePath, String suffix) {
  final left = basePath.endsWith('/')
      ? basePath.substring(0, basePath.length - 1)
      : basePath;
  final right = suffix.startsWith('/') ? suffix : '/$suffix';
  if (left.isEmpty || left == '/') return right;
  return '$left$right';
}

/// FlutterPatch CLI local artifact cache:
/// `~/.flutterpatch/bin/cache/flutterpatch` (or beside `FLUTTERPATCH_BIN`).
Directory resolveFlutterPatchArtifactCacheRoot([
  Map<String, String>? environment,
]) {
  final env = environment ?? Platform.environment;
  final fromBin = (env['FLUTTERPATCH_BIN'] ?? '').trim();
  if (fromBin.isNotEmpty) {
    final cliDir = File(fromBin).parent;
    return Directory(join(cliDir.path, 'cache', 'flutterpatch'));
  }
  final home = (env['HOME'] ?? '').trim();
  if (home.isEmpty) {
    return Directory(join('.flutterpatch', 'bin', 'cache', 'flutterpatch'));
  }
  return Directory(
    join(home, '.flutterpatch', 'bin', 'cache', 'flutterpatch'),
  );
}

/// Stem under releases/patches: `android_aar` / `ios_xcframework` (+ `_N` for patch).
String flutterPatchArtifactMetaStem({
  required BuildType buildType,
  int? sourcePatchNumber,
}) {
  final base = switch (buildType) {
    BuildType.aar => 'android_aar',
    BuildType.framework => 'ios_xcframework',
    _ => 'ios_xcframework',
  };
  if (sourcePatchNumber != null) {
    return '${base}_$sourcePatchNumber';
  }
  return base;
}

/// Reads `hash` from FlutterPatch `*.meta.json` (same value as control-plane
/// `artifact_hash`). Falls back to SHA-256 of the sibling cached binary.
Future<String?> readFlutterPatchArtifactHashFromMeta({
  required Directory flutterDir,
  required BuildType buildType,
  required String releaseVersion,
  int? sourcePatchNumber,
  Map<String, String>? environment,
}) async {
  final version = releaseVersion.trim();
  if (version.isEmpty) return null;
  if (buildType != BuildType.aar && buildType != BuildType.framework) {
    return null;
  }

  final yaml = FlutterPatchYamlConfig.tryLoad(flutterDir);
  final appId = (yaml?.appId ?? '').trim();
  if (appId.isEmpty) {
    loggerWarning(
      'shorebird.yaml 缺少 app_id，无法读取 FlutterPatch artifact meta hash',
    );
    return null;
  }

  final cacheRoot = resolveFlutterPatchArtifactCacheRoot(environment);
  final kindDir = sourcePatchNumber != null ? 'patches' : 'releases';
  final stem = flutterPatchArtifactMetaStem(
    buildType: buildType,
    sourcePatchNumber: sourcePatchNumber,
  );
  final dir = Directory(join(cacheRoot.path, kindDir, appId, version));
  final metaFile = File(join(dir.path, '$stem.meta.json'));
  if (metaFile.existsSync()) {
    try {
      final decoded = jsonDecode(metaFile.readAsStringSync());
      if (decoded is Map) {
        final hash = '${decoded['hash'] ?? ''}'.trim();
        if (hash.isNotEmpty) {
          loggerInfo(
            'FlutterPatch artifact hash ← ${metaFile.path} '
            '(${hash.substring(0, hash.length < 12 ? hash.length : 12)}…)',
          );
          return hash;
        }
      }
    } catch (e) {
      loggerWarning('解析 FlutterPatch meta 失败 (${metaFile.path}): $e');
    }
  }

  final binFile = File(join(dir.path, stem));
  if (binFile.existsSync()) {
    final hash = (await sha256.bind(binFile.openRead()).first).toString();
    loggerInfo(
      'FlutterPatch artifact hash ← ${binFile.path} '
      '(${hash.substring(0, 12)}…)',
    );
    return hash;
  }

  loggerWarning(
    '未找到 FlutterPatch artifact meta/二进制: ${metaFile.path}',
  );
  return null;
}

/// Resolves contentHash for promote / cache index.
///
/// Prefer FlutterPatch CLI local `*.meta.json` `hash` (matches control-plane
/// `artifact_hash`). Android may fall back to hashing the `.aar` under
/// [buildCacheDir]. iOS no longer re-zips xcframework (that hash never matched
/// the uploaded package).
Future<String?> hashFlutterPatchPackageArtifact({
  required Directory buildCacheDir,
  required BuildType buildType,
  Directory? flutterDir,
  String? releaseVersion,
  int? sourcePatchNumber,
  Map<String, String>? environment,
}) async {
  final version = (releaseVersion ?? '').trim();
  if (flutterDir != null && version.isNotEmpty) {
    final fromMeta = await readFlutterPatchArtifactHashFromMeta(
      flutterDir: flutterDir,
      buildType: buildType,
      releaseVersion: version,
      sourcePatchNumber: sourcePatchNumber,
      environment: environment,
    );
    if (fromMeta != null && fromMeta.isNotEmpty) {
      return fromMeta;
    }
  }

  if (!buildCacheDir.existsSync()) return null;
  if (buildType == BuildType.aar) {
    File? best;
    await for (final entity in buildCacheDir.list(recursive: true)) {
      if (entity is! File) continue;
      final name = basename(entity.path);
      if (!name.endsWith('.aar')) continue;
      if (best == null ||
          name.startsWith('flutter_release-') ||
          entity.lengthSync() > best.lengthSync()) {
        best = entity;
        if (name.startsWith('flutter_release-')) break;
      }
    }
    if (best == null) return null;
    loggerWarning(
      'FlutterPatch meta 未命中，回退为本地 .aar SHA-256: ${best.path}',
    );
    return (await sha256.bind(best.openRead()).first).toString();
  }

  if (buildType == BuildType.framework) {
    loggerWarning(
      '无法从 FlutterPatch meta 读取 ios_xcframework artifact_hash；'
      '请确认 release/patch 已成功上传（勿再本地重 zip App.xcframework）。',
    );
  }
  return null;
}

/// Sidecar JSON embedded in metax framework/aar zip for cross-machine promote.
Map<String, dynamic> buildMetaxArtifactSidecar({
  required String contentHash,
  required String releaseVersion,
  int? sourcePatchNumber,
}) {
  return <String, dynamic>{
    'contentHash': contentHash,
    'releaseVersion': releaseVersion,
    if (sourcePatchNumber != null) 'sourcePatchNumber': sourcePatchNumber,
  };
}

void writeMetaxArtifactSidecar({
  required Directory buildCacheDir,
  required String contentHash,
  required String releaseVersion,
  int? sourcePatchNumber,
}) {
  final hash = contentHash.trim();
  if (hash.isEmpty || !buildCacheDir.existsSync()) return;
  final file = File(join(buildCacheDir.path, kMetaxArtifactSidecarFileName));
  file.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(
      buildMetaxArtifactSidecar(
        contentHash: hash,
        releaseVersion: releaseVersion,
        sourcePatchNumber: sourcePatchNumber,
      ),
    ),
  );
}

/// Reads [kMetaxArtifactSidecarFileName] from a metax cache zip (if present).
Map<String, dynamic>? readMetaxArtifactSidecarFromZip(File zipFile) {
  if (!zipFile.existsSync()) return null;
  try {
    final result = Process.runSync('unzip', [
      '-p',
      zipFile.path,
      kMetaxArtifactSidecarFileName,
    ]);
    if (result.exitCode != 0) {
      // Also try with ./ prefix some zip tools use
      final alt = Process.runSync('unzip', [
        '-p',
        zipFile.path,
        './$kMetaxArtifactSidecarFileName',
      ]);
      if (alt.exitCode != 0) return null;
      final decoded = jsonDecode(alt.stdout.toString());
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return null;
    }
    final decoded = jsonDecode(result.stdout.toString());
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
  } catch (e) {
    loggerWarning('读取缓存 zip 内 $kMetaxArtifactSidecarFileName 失败: $e');
  }
  return null;
}

/// 清理 FlutterPatch 共用的 `flutter/release`，避免跨平台产物混入。
Future<void> clearFlutterPatchReleaseDir(Directory flutterDir) async {
  final releaseDir = Directory(join(flutterDir.path, 'release'));
  if (!await releaseDir.exists()) {
    return;
  }
  await releaseDir.delete(recursive: true);
  loggerInfo('已清理旧 FlutterPatch release 目录: ${releaseDir.path}');
}

/// 从目录顶层移除 iOS framework 残留（xcframework / podspec / Privacys）。
Future<int> stripIosArtifactsFromCacheDir(Directory dir) async {
  if (!await dir.exists()) {
    return 0;
  }
  var removed = 0;
  await for (final entity in dir.list(followLinks: false)) {
    final name = basename(entity.path);
    final shouldRemove = (entity is Directory &&
            (name.endsWith('.xcframework') || name == 'Privacys')) ||
        (entity is File &&
            (name.endsWith('.podspec') ||
                name == 'Podfile' ||
                name == 'Podfile.lock'));
    if (!shouldRemove) {
      continue;
    }
    await entity.delete(recursive: true);
    removed++;
  }
  if (removed > 0) {
    loggerWarning(
      '已从 ${dir.path} 剥离 $removed 个 iOS 残留产物（避免污染 Android 缓存）',
    );
  }
  return removed;
}

/// 从目录顶层移除 Android AAR/Maven 残留。
Future<int> stripAndroidArtifactsFromCacheDir(Directory dir) async {
  if (!await dir.exists()) {
    return 0;
  }
  var removed = 0;
  await for (final entity in dir.list(followLinks: false)) {
    final name = basename(entity.path);
    final shouldRemove = (entity is Directory && name == 'android_generated') ||
        (entity is File && name.endsWith('.aar'));
    if (!shouldRemove) {
      continue;
    }
    await entity.delete(recursive: true);
    removed++;
  }
  if (removed > 0) {
    loggerWarning(
      '已从 ${dir.path} 剥离 $removed 个 Android 残留产物（避免污染 iOS 缓存）',
    );
  }
  return removed;
}

Future<int?> runFlutterPatchPatch({
  required Directory flutterDir,
  required String platform, // ios-framework | aar
  required String releaseVersion,
  bool allowAssetDiffs = false,
  /// `true`/`false` 显式开关白名单；`null` 不传（由 CLI/unique-ids 默认行为决定）。
  bool? whitelist,
  List<String> uniqueIds = const [],
}) async {
  await ensureFlutterPatchInstalled();
  // iOS / Android 共用 flutter/release；不清空会把上一平台残留误当成下一平台产物。
  await clearFlutterPatchReleaseDir(flutterDir);
  final cli = resolveFlutterPatchCli();
  final args = buildFlutterPatchPatchArgs(
    platform: platform,
    releaseVersion: releaseVersion,
    allowAssetDiffs: allowAssetDiffs,
    whitelist: whitelist,
    uniqueIds: uniqueIds,
  );
  loggerInfo('执行: $cli ${args.join(' ')}');
  final sw = Stopwatch()..start();
  try {
    final result = await ProcessRunner(environment: flutterPatchCliEnvironment())
        .runProcess(
      [cli, ...args],
      workingDirectory: flutterDir,
      printOutput: true,
    );
    loggerInfo(
      'shell 完成: $cli ${args.take(2).join(' ')} · '
      '用时 ${formatElapsedDuration(sw.elapsed)}',
    );
    return parseFlutterPatchPublishedPatchNumber(
      '${result.stdout}\n${result.stderr}',
    );
  } catch (e) {
    loggerInfo(
      'shell 失败: $cli ${args.take(2).join(' ')} · '
      '用时 ${formatElapsedDuration(sw.elapsed)}',
    );
    rethrow;
  }
}

/// Parses `✅ Published Patch N!` from flutterpatch patch stdout.
int? parseFlutterPatchPublishedPatchNumber(String output) {
  final match = RegExp(r'Published Patch\s+(\d+)').firstMatch(output);
  if (match == null) return null;
  return int.tryParse(match.group(1)!);
}

/// `release/` / framework 目录是否含 iOS xcframework（相对 Android Maven 残留）。
bool looksLikeIosFrameworkDir(Directory dir) {
  if (!dir.existsSync()) return false;
  for (final name in const [
    'ShorebirdFlutter.xcframework',
    'Flutter.xcframework',
    'App.xcframework',
  ]) {
    if (Directory(join(dir.path, name)).existsSync()) {
      return true;
    }
  }
  return false;
}

/// 将 FlutterPatch iOS release 产物同步到 metax 习惯的 framework 缓存目录
Future<void> syncFlutterPatchIosReleaseToFrameworkDir(Directory flutterDir) async {
  final releaseDir = Directory(join(flutterDir.path, 'release'));
  final targetDir =
      Directory(join(flutterDir.path, 'build', 'ios', 'framework', 'Release'));

  // patch 常把 framework 写到 build/ios/framework；release/ 可能仍是上一平台 Android 残留。
  // 仅当 release/ 真有 iOS xcframework 时才覆盖 build 目录。
  if (looksLikeIosFrameworkDir(releaseDir)) {
    if (targetDir.existsSync()) {
      await targetDir.delete(recursive: true);
    }
    await targetDir.create(recursive: true);
    await copyDirToDir(releaseDir, targetDir);
    loggerInfo('已从 FlutterPatch release 同步产物到 ${targetDir.path}');
  } else if (targetDir.existsSync() && looksLikeIosFrameworkDir(targetDir)) {
    if (releaseDir.existsSync()) {
      loggerWarning(
        'release/ 无 iOS xcframework（可能是 Android 残留），'
        '保留已有产物目录: ${targetDir.path}',
      );
    } else {
      // flutterpatch release 上传失败时，可能只留下 build 目录产物
      loggerWarning(
        '未找到 ${releaseDir.path}，改用已有产物目录: ${targetDir.path}',
      );
    }
  } else {
    throw Exception(
      'FlutterPatch iOS 产物不存在（需要 ${releaseDir.path} 或 ${targetDir.path} '
      '含 ShorebirdFlutter/Flutter/App.xcframework）',
    );
  }

  await stripAndroidArtifactsFromCacheDir(targetDir);

  // FlutterPatch 产出 ShorebirdFlutter.xcframework（内含 Flutter.framework）。
  // CocoaPods 按 xcframework 文件名链接，必须改回 Flutter.xcframework，否则会报
  // framework 'ShorebirdFlutter' not found。
  final flutterXc = Directory(join(targetDir.path, 'Flutter.xcframework'));
  final flutterpatchXc =
      Directory(join(targetDir.path, 'ShorebirdFlutter.xcframework'));
  if (flutterpatchXc.existsSync()) {
    if (flutterXc.existsSync()) {
      await flutterXc.delete(recursive: true);
    }
    await flutterpatchXc.rename(flutterXc.path);
    loggerInfo(
      '已将 ShorebirdFlutter.xcframework 重命名为 Flutter.xcframework（CocoaPods 链接）',
    );
  }
  if (flutterXc.existsSync()) {
    final flutterPodspec = File(join(targetDir.path, 'Flutter.podspec'));
    await flutterPodspec.writeAsString('''
#
# FlutterPatch 引擎对外仍暴露为 Flutter pod。
# 必须使用 Flutter.xcframework 文件名，否则 CocoaPods 会错误链接 ShorebirdFlutter。
#

Pod::Spec.new do |s|
  s.name                  = 'Flutter'
  s.version               = '1.0.0'
  s.summary               = 'Flutter engine (FlutterPatch)'
  s.description           = 'FlutterPatch engine exposed as Flutter for CocoaPods'
  s.homepage              = 'https://flutter.dev'
  s.license               = { :type => 'BSD' }
  s.author                = { 'Flutter Dev Team' => 'flutter-dev@googlegroups.com' }
  s.source                = { :path => '.' }
  s.platform              = :ios, '13.0'
  s.vendored_frameworks   = 'Flutter.xcframework'
end
''');
    loggerInfo('已写入 Flutter.podspec（vendored Flutter.xcframework / FlutterPatch）');
    final staleFlutterPatchPodspec =
        File(join(targetDir.path, 'ShorebirdFlutter.podspec'));
    if (staleFlutterPatchPodspec.existsSync()) {
      await staleFlutterPatchPodspec.delete();
      loggerInfo('已删除错误的 ShorebirdFlutter.podspec');
    }
  } else {
    throw Exception(
      'FlutterPatch sync 后未找到 Flutter.xcframework: ${flutterXc.path}',
    );
  }

  loggerInfo('已完成 FlutterPatch iOS 产物同步: ${targetDir.path}');
}

/// FlutterPatch / flutter build aar 的 Maven 仓库相对路径（相对 build/host）。
///
/// Android `settings.gradle` 与普通 `flutter build aar` 均约定：
/// `build/host/outputs/repo` → 解压后为 `android/aar/flutter/outputs/repo`。
const kFlutterAarMavenRepoRelativePath = 'outputs/repo';

/// FlutterPatch `release/` 可能是 Maven 根，也可能已含 `outputs/repo`。
Directory resolveFlutterPatchAarMavenSource(Directory releaseOrHostDir) {
  final nested = Directory(
    join(releaseOrHostDir.path, kFlutterAarMavenRepoRelativePath),
  );
  if (nested.existsSync()) {
    return nested;
  }
  return releaseOrHostDir;
}

bool _looksLikeMavenRepoRoot(Directory dir) {
  if (!dir.existsSync()) return false;
  // flutter / flutterpatch AAR 常见顶层：groupId 目录或 android_generated
  for (final name in const ['com', 'io', 'dev', 'android_generated']) {
    if (Directory(join(dir.path, name)).existsSync()) {
      return true;
    }
  }
  return false;
}

/// 将已有 `build/host` 对齐为 `outputs/repo` 布局（兼容旧 FlutterPatch 扁平产物）。
Future<void> ensureFlutterPatchHostDirHasOutputsRepo(Directory hostDir) async {
  final outputsRepo = Directory(
    join(hostDir.path, kFlutterAarMavenRepoRelativePath),
  );
  if (outputsRepo.existsSync() && _looksLikeMavenRepoRoot(outputsRepo)) {
    return;
  }
  if (!_looksLikeMavenRepoRoot(hostDir)) {
    // 既没有扁平 Maven，也没有 outputs/repo：保持原样，由后续校验报错
    return;
  }

  final staging = Directory(join(hostDir.path, '.flutterpatch_repo_staging'));
  if (staging.existsSync()) {
    await staging.delete(recursive: true);
  }
  await staging.create();

  await for (final entity in hostDir.list(followLinks: false)) {
    final name = basename(entity.path);
    // cache.json 留在 host 根，与 flutter build aar 缓存一致
    if (name == '.flutterpatch_repo_staging' ||
        name == 'cache.json' ||
        name == 'outputs') {
      continue;
    }
    await entity.rename(join(staging.path, name));
  }

  if (outputsRepo.existsSync()) {
    await outputsRepo.delete(recursive: true);
  }
  await outputsRepo.create(recursive: true);
  await for (final entity in staging.list(followLinks: false)) {
    await entity.rename(join(outputsRepo.path, basename(entity.path)));
  }
  await staging.delete(recursive: true);
  loggerInfo('已将 build/host 扁平 Maven 对齐到 ${outputsRepo.path}');
}

/// 将 FlutterPatch AAR release 产物同步到 flutter build aar 习惯目录
///
/// FlutterPatch 默认写出 `release/<maven-root>`（无 `outputs/repo`），
/// 而 metax 缓存 / Android 依赖约定为 `build/host/outputs/repo`。
Future<void> syncFlutterPatchAarReleaseToHostDir(Directory flutterDir) async {
  final releaseDir = Directory(join(flutterDir.path, 'release'));
  final hostDir = Directory(join(flutterDir.path, 'build', 'host'));
  final outputsRepoDir = Directory(
    join(hostDir.path, kFlutterAarMavenRepoRelativePath),
  );

  if (releaseDir.existsSync()) {
    final mavenSource = resolveFlutterPatchAarMavenSource(releaseDir);
    if (hostDir.existsSync()) {
      await hostDir.delete(recursive: true);
    }
    await outputsRepoDir.create(recursive: true);
    await copyDirToDir(mavenSource, outputsRepoDir);
    // 防御：即使 release 未清空，也不要把 iOS xcframework 打进 android 缓存
    await stripIosArtifactsFromCacheDir(hostDir);
    await stripIosArtifactsFromCacheDir(outputsRepoDir);
    loggerInfo('已同步 FlutterPatch AAR 产物到 ${outputsRepoDir.path}');
    return;
  }

  // 部分版本可能直接写到 build/host
  if (!hostDir.existsSync()) {
    throw Exception('FlutterPatch AAR release 目录不存在: ${releaseDir.path}');
  }
  await ensureFlutterPatchHostDirHasOutputsRepo(hostDir);
  await stripIosArtifactsFromCacheDir(hostDir);
  if (outputsRepoDir.existsSync()) {
    await stripIosArtifactsFromCacheDir(outputsRepoDir);
  }
  loggerInfo(
    '使用已有 build/host 作为 AAR 产物目录（已对齐 $kFlutterAarMavenRepoRelativePath）',
  );
}
