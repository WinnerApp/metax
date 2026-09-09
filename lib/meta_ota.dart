import 'dart:convert';
import 'dart:io';

import 'package:meta_tool/app_home_dir.dart';
import 'package:meta_tool/common.dart';
import 'package:meta_tool/estimated_progress.dart';
import 'package:meta_tool/shorebird.dart';
import 'package:path/path.dart';
import 'package:process_runner/process_runner.dart';

/// 与 meta_ota CLI 对齐的配置文件读取。
///
/// 优先级（CLI 文档）: `--api/--token` > 环境变量 > `.meta_ota.json` >
/// `~/.meta_ota/config.json`。此处不含 CLI flag，由调用方自行覆盖。
class MetaOtaFileConfig {
  final String? api;
  final String? token;

  const MetaOtaFileConfig({this.api, this.token});
}

Map<String, dynamic>? _readMetaOtaJson(File file) {
  if (!file.existsSync()) return null;
  try {
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
  } catch (e) {
    loggerWarning('读取 ${file.path} 失败: $e');
  }
  return null;
}

/// 读取项目 / 用户级 meta_ota 配置（后者补前者未设字段）。
MetaOtaFileConfig loadMetaOtaFileConfig(
  Directory flutterDir, {
  Map<String, String>? environment,
}) {
  String? api;
  String? token;
  final env = environment ?? Platform.environment;

  void merge(Map<String, dynamic>? json) {
    if (json == null) return;
    api ??= (json['api'] ?? json['META_OTA_API'])?.toString().trim();
    token ??= (json['token'] ?? json['META_OTA_TOKEN'])?.toString().trim();
    if (api != null && api!.isEmpty) api = null;
    if (token != null && token!.isEmpty) token = null;
  }

  merge(_readMetaOtaJson(File(join(flutterDir.path, '.meta_ota.json'))));
  merge(
    _readMetaOtaJson(
      File(join(env['HOME'] ?? '', '.meta_ota', 'config.json')),
    ),
  );

  return MetaOtaFileConfig(api: api, token: token);
}

bool _looksLikeHttpUrl(String value) {
  final v = value.trim().toLowerCase();
  return v.startsWith('http://') || v.startsWith('https://');
}

/// 解析 Meta OTA API / token / app_id（与 meta_ota CLI 优先级对齐）。
class MetaOtaCredentials {
  final String api;
  final String token;
  final String appId;

  const MetaOtaCredentials({
    required this.api,
    required this.token,
    required this.appId,
  });
}

/// 解析凭证；缺项时返回 `null`（由调用方决定跳过或报错）。
MetaOtaCredentials? tryResolveMetaOtaCredentials({
  required Directory flutterDir,
  Map<String, String>? environment,
  bool requireAppId = false,
}) {
  final env = environment ?? Platform.environment;
  final yaml = ShorebirdYamlConfig.tryLoad(flutterDir);
  final fileCfg = loadMetaOtaFileConfig(flutterDir, environment: env);

  var api = (env['META_OTA_API'] ?? '').trim();
  if (api.isEmpty) api = (fileCfg.api ?? '').trim();
  if (api.isNotEmpty && !_looksLikeHttpUrl(api)) {
    loggerWarning(
      'meta_ota 配置里的 api="$api" 不像 URL（应以 http(s):// 开头）。'
      '将回退 shorebird.yaml base_url / META_OTA_API。'
      '请执行: meta_ota config --api <OTA地址> --token <API Key>',
    );
    api = '';
  }
  if (api.isEmpty) api = (yaml?.baseUrl ?? '').trim();

  var token = (env['META_OTA_TOKEN'] ?? '').trim();
  if (token.isEmpty) token = (fileCfg.token ?? '').trim();

  final appId = (env['META_OTA_APP_ID'] ?? yaml?.appId ?? '').trim();

  if (api.isEmpty || token.isEmpty) return null;
  if (requireAppId && appId.isEmpty) return null;

  return MetaOtaCredentials(
    api: api.replaceAll(RegExp(r'/$'), ''),
    token: token,
    appId: appId,
  );
}

/// 解析 `meta_ota` 可执行文件。
///
/// 优先级：
/// 1. `META_OTA_BIN`（绝对路径或 PATH 中的名字）
/// 2. `META_CODE_PUSH_ROOT/dist/meta_ota` 或 `.../scripts/meta_ota.sh`
/// 3. `which meta_ota`
Future<String> resolveMetaOtaBin({Map<String, String>? environment}) async {
  final env = environment ?? Platform.environment;

  final explicit = (env['META_OTA_BIN'] ?? '').trim();
  if (explicit.isNotEmpty) {
    final asFile = File(explicit);
    if (asFile.existsSync()) return asFile.absolute.path;
    // 可能是 PATH 里的命令名
    try {
      final which = await ProcessRunner().runProcess(
        ['which', explicit],
        printOutput: false,
      );
      final path = which.stdout.trim();
      if (path.isNotEmpty) return path;
    } catch (_) {}
    throw Exception('META_OTA_BIN 无效: $explicit');
  }

  final root = (env['META_CODE_PUSH_ROOT'] ?? '').trim();
  if (root.isNotEmpty) {
    final candidates = [
      join(root, 'dist', 'meta_ota'),
      join(root, 'packages', 'ota_cli', 'build', 'meta_ota'),
      join(root, 'scripts', 'meta_ota.sh'),
    ];
    for (final path in candidates) {
      final f = File(path);
      if (f.existsSync()) return f.absolute.path;
    }
    throw Exception(
      'META_CODE_PUSH_ROOT=$root 下未找到 meta_ota'
      '（期望 dist/meta_ota 或 scripts/meta_ota.sh）',
    );
  }

  try {
    final which = await ProcessRunner().runProcess(
      ['which', 'meta_ota'],
      printOutput: false,
    );
    final path = which.stdout.trim();
    if (path.isNotEmpty) return path;
  } catch (_) {}

  throw Exception(
    '未找到 meta_ota CLI。请安装/编译 meta_code_push 的 ota_cli，'
    '并设置 META_OTA_BIN，或将 meta_ota 加入 PATH，'
    '或设置 META_CODE_PUSH_ROOT 指向 meta_code_push 仓库根目录。',
  );
}

class MetaOtaUploadResult {
  final String stdout;
  final String? patchId;

  const MetaOtaUploadResult({
    required this.stdout,
    this.patchId,
  });
}

String? _parsePatchId(String output) {
  // meta_ota 会打印 JSON（含 "id"）以及 promote 日志里的 id=
  final jsonId = RegExp(r'"id"\s*:\s*"([^"]+)"').firstMatch(output);
  if (jsonId != null) return jsonId.group(1);
  final promoteId = RegExp(r'id=([0-9a-fA-F-]{8,})').firstMatch(output);
  if (promoteId != null) return promoteId.group(1);
  return null;
}

/// 与 meta_ota `androidAbiSubdir` 对齐。
String metaOtaAndroidAbiSubdir(String arch) {
  switch (arch.trim()) {
    case 'aarch64':
    case 'arm64':
      return 'arm64-v8a';
    case 'arm':
      return 'armeabi-v7a';
    case 'x86_64':
      return 'x86_64';
    default:
      return arch.trim();
  }
}

File? _newestLibappUnder(Directory root, String abi) {
  if (!root.existsSync()) return null;
  File? best;
  DateTime? bestM;
  for (final entity in root.listSync(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    if (basename(entity.path) != 'libapp.so') continue;
    // 只认对应 ABI，避免误取 x86_64 / armeabi-v7a
    final parent = basename(dirname(entity.path));
    if (parent != abi) continue;
    final m = entity.lastModifiedSync();
    if (bestM == null || m.isAfter(bestM)) {
      bestM = m;
      best = entity;
    }
  }
  return best;
}

/// 解析 meta_ota upload 需要的 patched binary。
///
/// meta_ota 默认只认完整 Flutter App 路径
/// `build/app/intermediates/.../lib/{abi}/libapp.so`；
/// add-to-app / `shorebird patch aar` 产物在 `build/host/.../jni/{abi}/libapp.so`。
///
/// 优先级：
/// 1. `META_OTA_PATCH_LIBAPP` / [explicitPatchLibapp]
/// 2. meta_ota 完整 App 默认路径
/// 3. AAR host Maven jni
/// 4. `.android` / `build` 下同 ABI 最新 `libapp.so`
/// 5. iOS: `build/out.vmcode`
String? resolveMetaOtaPatchedBinary({
  required Directory flutterDir,
  required String platform, // android | ios
  String arch = 'aarch64',
  String? explicitPatchLibapp,
  Map<String, String>? environment,
}) {
  final env = environment ?? Platform.environment;
  final fromEnv = (explicitPatchLibapp ?? env['META_OTA_PATCH_LIBAPP'] ?? '')
      .trim();
  if (fromEnv.isNotEmpty) {
    final f = File(fromEnv);
    if (f.existsSync()) return f.absolute.path;
    throw Exception('META_OTA_PATCH_LIBAPP 无效或不存在: $fromEnv');
  }

  final appDir = flutterDir.path;
  if (platform == 'ios') {
    final vmcode = File(join(appDir, 'build', 'out.vmcode'));
    if (vmcode.existsSync()) return vmcode.absolute.path;
    return null;
  }

  if (platform != 'android') return null;

  final abi = metaOtaAndroidAbiSubdir(arch);
  final fullAppDefault = File(
    join(
      appDir,
      'build/app/intermediates/stripped_native_libs/release/'
      'stripReleaseDebugSymbols/out/lib',
      abi,
      'libapp.so',
    ),
  );
  if (fullAppDefault.existsSync()) {
    return fullAppDefault.absolute.path;
  }

  final hostRepo = Directory(join(appDir, 'build', 'host', 'outputs', 'repo'));
  final fromHost = _newestLibappUnder(hostRepo, abi);
  if (fromHost != null) return fromHost.absolute.path;

  // 部分版本写在 release/ 或未 sync 的 host
  final fromRelease = _newestLibappUnder(
    Directory(join(appDir, 'release')),
    abi,
  );
  if (fromRelease != null) return fromRelease.absolute.path;

  final fromAndroidModule = _newestLibappUnder(
    Directory(join(appDir, '.android')),
    abi,
  );
  if (fromAndroidModule != null) return fromAndroidModule.absolute.path;

  final fromBuild = _newestLibappUnder(Directory(join(appDir, 'build')), abi);
  return fromBuild?.absolute.path;
}

bool _envFlagTrue(Map<String, String> env, String key) {
  final v = (env[key] ?? '').trim().toLowerCase();
  return v == 'true' || v == '1';
}

String? _resolveMetaOtaAppId(Directory flutterDir, Map<String, String> env) {
  final fromEnv = (env['META_OTA_APP_ID'] ?? '').trim();
  if (fromEnv.isNotEmpty) return fromEnv;
  final fromYaml = ShorebirdYamlConfig.tryLoad(flutterDir)?.appId?.trim();
  if (fromYaml != null && fromYaml.isNotEmpty) return fromYaml;
  return null;
}

const _kPlaceholderAppId = '00000000-0000-4000-8000-000000000001';

Future<void> _runMetaOtaQuietly({
  required String bin,
  required List<String> args,
  required Directory workingDirectory,
  Map<String, String>? environment,
  required String successLog,
  required String failureLog,
}) async {
  loggerInfo('执行: $bin ${args.join(' ')}');
  final sw = Stopwatch()..start();
  try {
    await ProcessRunner(
      environment: environment == null
          ? null
          : Map<String, String>.from(environment),
    ).runProcess(
      [bin, ...args],
      workingDirectory: workingDirectory,
      printOutput: true,
    );
    loggerSuccess('$successLog · 用时 ${formatElapsedDuration(sw.elapsed)}');
  } catch (e) {
    loggerWarning('$failureLog: $e');
  }
}

/// 在 shorebird release 之后，委托 `meta_ota admin upload-release` 向自建 OTA 登记版本。
///
/// 对齐 meta_ota CLI 的 `release` 成功后行为（仅控制面登记，不再次执行 shorebird）。
/// 鉴权由本机 meta_ota（`~/.meta_ota` / `.meta_ota.json`）完成，不传 `--api/--token`，也不注入凭证环境变量。
/// 设置 `META_OTA_SKIP_RELEASE_SYNC=true` 可显式跳过。
Future<void> syncShorebirdReleaseToMetaOta({
  required AppHomeDir appHomeDir,
  required String platform, // android | ios
  required String releaseVersion,
  Map<String, String>? environment,
}) async {
  final env = Map<String, String>.from(environment ?? Platform.environment);
  if (_envFlagTrue(env, 'META_OTA_SKIP_RELEASE_SYNC')) {
    loggerInfo('META_OTA_SKIP_RELEASE_SYNC 已设置，跳过向自建 OTA 登记 release');
    return;
  }

  final appId = _resolveMetaOtaAppId(appHomeDir.flutterDir, env);
  if (appId == _kPlaceholderAppId) {
    loggerWarning('app_id 为占位值，跳过向自建 OTA 登记 release');
    return;
  }

  final String bin;
  try {
    bin = await resolveMetaOtaBin(environment: env);
  } catch (e) {
    loggerWarning('未找到 meta_ota，跳过向自建 OTA 登记 release: $e');
    return;
  }

  final arch = (env['META_OTA_ARCH'] ?? 'aarch64').trim();
  final args = <String>[
    'admin',
    'upload-release',
    '--version',
    releaseVersion,
    '--platform',
    platform,
    '--arch',
    arch,
  ];
  if (appId != null && appId.isNotEmpty) {
    args.addAll(['--app-id', appId]);
  }

  final artifact = (env['META_OTA_RELEASE_ARTIFACT'] ?? '').trim();
  if (artifact.isNotEmpty) {
    args.addAll(['--artifact', artifact]);
  }

  loggerInfo(
    '向自建 OTA 登记 release: $releaseVersion ($platform/$arch) '
    'via meta_ota admin upload-release',
  );

  await _runMetaOtaQuietly(
    bin: bin,
    args: args,
    workingDirectory: appHomeDir.flutterDir,
    environment: environment,
    successLog: '已向自建 OTA 登记 release: $releaseVersion',
    failureLog: 'meta_ota admin upload-release 失败（不影响 Shorebird 产物）',
  );
  if (!_envFlagTrue(env, 'META_OTA_SKIP_BASELINE_SYNC')) {
    await syncShorebirdBaselineToMetaOta(
      appHomeDir: appHomeDir,
      releaseVersion: releaseVersion,
      environment: environment,
    );
  }
}

/// Shorebird release 登记后，上传 OTA 快照 + 资源配置基线。
///
/// - `meta_ota upload-snapshot`
/// - `meta_ota upload-resources`
///
/// 在仓库**主目录**（workspace）执行。鉴权由本机 meta_ota 完成。
/// 失败只告警，不阻断打包。`META_OTA_SKIP_BASELINE_SYNC=true` 可跳过。
Future<void> syncShorebirdBaselineToMetaOta({
  required AppHomeDir appHomeDir,
  required String releaseVersion,
  Map<String, String>? environment,
}) async {
  final env = Map<String, String>.from(environment ?? Platform.environment);
  if (_envFlagTrue(env, 'META_OTA_SKIP_RELEASE_SYNC') ||
      _envFlagTrue(env, 'META_OTA_SKIP_BASELINE_SYNC')) {
    loggerInfo('已跳过 meta_ota upload-snapshot / upload-resources');
    return;
  }

  final appId = _resolveMetaOtaAppId(appHomeDir.flutterDir, env);
  if (appId == _kPlaceholderAppId) {
    loggerWarning('app_id 为占位值，跳过 upload-snapshot / upload-resources');
    return;
  }

  final String bin;
  try {
    bin = await resolveMetaOtaBin(environment: env);
  } catch (e) {
    loggerWarning('未找到 meta_ota，跳过 upload-snapshot / upload-resources: $e');
    return;
  }

  // AOT 快照 + 资源配置：在主仓目录执行，路径相对 workspace。
  final workspace = appHomeDir.directory;
  final flutterRel = relative(appHomeDir.flutterDir.path, from: workspace.path);

  final snapshotArgs = <String>[
    'upload-snapshot',
    '--flutter',
    flutterRel,
    '--version',
    releaseVersion,
  ];
  if (appHomeDir.androidDir.existsSync()) {
    snapshotArgs.addAll([
      '--android',
      relative(appHomeDir.androidDir.path, from: workspace.path),
    ]);
  }
  if (appHomeDir.iosDir.existsSync()) {
    snapshotArgs.addAll([
      '--ios',
      relative(appHomeDir.iosDir.path, from: workspace.path),
    ]);
  }

  await _runMetaOtaQuietly(
    bin: bin,
    args: snapshotArgs,
    workingDirectory: workspace,
    environment: environment,
    successLog: '已上传 OTA 快照: $releaseVersion',
    failureLog: 'meta_ota upload-snapshot 失败（不影响 Shorebird 产物）',
  );

  await _runMetaOtaQuietly(
    bin: bin,
    args: [
      'upload-resources',
      '--app-dir',
      flutterRel,
      '--version',
      releaseVersion,
    ],
    workingDirectory: workspace,
    environment: environment,
    successLog: '已上传资源配置基线: $releaseVersion',
    failureLog: 'meta_ota upload-resources 失败（不影响 Shorebird 产物）',
  );
}

/// 热更后委托 `meta_ota upload-resource-pack` 上传有变动的资源包（独立于 Dart patch）。
///
/// 在 **Flutter 工程目录**（metaapp_flutter）执行。鉴权由本机 meta_ota 完成。
/// 失败只告警，不阻断已成功的补丁上传。
/// `META_OTA_SKIP_RESOURCE_PACK=true` 或 [skip]=true 可跳过。
Future<void> uploadMetaOtaResourcePack({
  required AppHomeDir appHomeDir,
  required String releaseVersion,
  String? channel,
  bool skip = false,
  Map<String, String>? environment,
}) async {
  final env = Map<String, String>.from(environment ?? Platform.environment);
  if (skip || _envFlagTrue(env, 'META_OTA_SKIP_RESOURCE_PACK')) {
    loggerInfo('已跳过 meta_ota upload-resource-pack');
    return;
  }

  final String bin;
  try {
    bin = await resolveMetaOtaBin(environment: env);
  } catch (e) {
    loggerWarning('未找到 meta_ota，跳过 upload-resource-pack: $e');
    return;
  }

  final args = <String>[
    'upload-resource-pack',
    '--app-dir',
    '.',
    '--version',
    releaseVersion,
  ];
  final ch = (channel ?? '').trim();
  if (ch.isNotEmpty) {
    args.addAll(['--channel', ch]);
  }

  await _runMetaOtaQuietly(
    bin: bin,
    args: args,
    workingDirectory: appHomeDir.flutterDir,
    environment: environment,
    successLog: '已处理资源包上传: $releaseVersion',
    failureLog: 'meta_ota upload-resource-pack 失败（不影响 Dart 补丁）',
  );
}

/// 在 shorebird patch 之后，委托外部 `meta_ota upload` 推送到 Meta Code Push。
///
/// 不自实现 HTTP；上传/promote/check 均由 meta_ota CLI 完成。
/// 鉴权由本机 meta_ota 完成，不传 `--api/--token`，也不注入凭证环境变量。
/// 注意：当前 meta_ota `upload` 固定 promote → stable（无 skip-promote / 自定义 channel）。
Future<MetaOtaUploadResult> uploadShorebirdPatchToMetaOta({
  required AppHomeDir appHomeDir,
  required String platform, // android | ios
  required String releaseVersion,
  String? channel,
  bool promote = true,
  Map<String, String>? environment,
}) async {
  final env = Map<String, String>.from(environment ?? Platform.environment);

  if (!promote) {
    loggerWarning(
      'meta_ota upload 目前总会 promote；--skip-promote 无法生效，已忽略',
    );
  }
  final promoteChannel = channel ?? (env['META_OTA_CHANNEL'] ?? 'stable').trim();
  if (promoteChannel.isNotEmpty && promoteChannel != 'stable') {
    loggerWarning(
      'meta_ota upload 目前固定 promote → stable；'
      '--channel=$promoteChannel 无法传给 CLI，已忽略',
    );
  }

  final bin = await resolveMetaOtaBin(environment: env);
  final arch = (env['META_OTA_ARCH'] ?? 'aarch64').trim();
  final appDir = appHomeDir.flutterDir.path;

  final args = <String>[
    'upload',
    platform,
    '--app-dir',
    appDir,
    '--version',
    releaseVersion,
    '--arch',
    arch,
  ];

  // 可选透传产物路径（与 meta_ota / 环境变量约定一致）
  void addIfEnv(String flag, String envKey) {
    final v = (env[envKey] ?? '').trim();
    if (v.isNotEmpty) {
      args.addAll([flag, v]);
    }
  }

  // AAR / add-to-app：meta_ota 默认路径不存在时，自动补 --patch-libapp
  final hasExplicitPatchLibapp =
      (env['META_OTA_PATCH_LIBAPP'] ?? '').trim().isNotEmpty;
  if (!hasExplicitPatchLibapp) {
    final resolved = resolveMetaOtaPatchedBinary(
      flutterDir: appHomeDir.flutterDir,
      platform: platform,
      arch: arch,
      environment: env,
    );
    if (resolved != null) {
      args.addAll(['--patch-libapp', resolved]);
      loggerInfo('meta_ota patched binary: $resolved');
    } else if (platform == 'android') {
      loggerWarning(
        '未自动找到 android libapp.so（完整 App 或 AAR jni）。'
        '可设置 META_OTA_PATCH_LIBAPP 后重试。',
      );
    }
  }

  addIfEnv('--patch-libapp', 'META_OTA_PATCH_LIBAPP');
  addIfEnv('--patch-file', 'META_OTA_PATCH_FILE');
  addIfEnv('--hash', 'META_OTA_LIBAPP_HASH');
  addIfEnv('--release-libapp', 'META_OTA_RELEASE_LIBAPP');

  loggerInfo('执行: $bin ${args.join(' ')}');

  final sw = Stopwatch()..start();
  final ProcessRunnerResult result;
  try {
    result = await ProcessRunner(
      environment: environment == null
          ? null
          : Map<String, String>.from(environment),
    ).runProcess(
      [bin, ...args],
      workingDirectory: appHomeDir.flutterDir,
      printOutput: true,
    );
    loggerInfo(
      'shell 完成: $bin upload · 用时 ${formatElapsedDuration(sw.elapsed)}',
    );
  } catch (e) {
    loggerInfo(
      'shell 失败: $bin upload · 用时 ${formatElapsedDuration(sw.elapsed)}',
    );
    throw Exception('meta_ota upload 失败: $e');
  }

  final output = '${result.stdout}\n${result.stderr}';
  final patchId = _parsePatchId(output);
  return MetaOtaUploadResult(stdout: output, patchId: patchId);
}
