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

/// 在 shorebird patch 之后，委托外部 `meta_ota upload` 推送到 Meta Code Push。
///
/// 不自实现 HTTP；上传/promote/check 均由 meta_ota CLI 完成。
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
  final yaml = ShorebirdYamlConfig.tryLoad(appHomeDir.flutterDir);
  final fileCfg = loadMetaOtaFileConfig(
    appHomeDir.flutterDir,
    environment: env,
  );

  // 与 meta_ota 一致：环境变量 > .meta_ota.json / ~/.meta_ota/config.json
  // API 额外可用 shorebird.yaml base_url。
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

  if (api.isEmpty) {
    throw Exception(
      '缺少 Meta OTA API 地址。请设置 META_OTA_API、'
      '或 shorebird.yaml base_url、'
      '或 meta_ota config --api <URL>。',
    );
  }
  if (token.isEmpty) {
    throw Exception(
      '缺少 Meta OTA Token。请设置 META_OTA_TOKEN，'
      '或执行 meta_ota config --token <API Key>'
      '（写入 ~/.meta_ota/config.json / .meta_ota.json）。',
    );
  }

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
    '--api',
    api.replaceAll(RegExp(r'/$'), ''),
    '--token',
    token,
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

  final logArgs = List<String>.from(args);
  final tokenIdx = logArgs.indexOf('--token');
  if (tokenIdx >= 0 && tokenIdx + 1 < logArgs.length) {
    logArgs[tokenIdx + 1] = '***';
  }
  loggerInfo('执行: $bin ${logArgs.join(' ')}');

  final cliEnv = Map<String, String>.from(env);
  cliEnv['META_OTA_API'] = api.replaceAll(RegExp(r'/$'), '');
  cliEnv['META_OTA_TOKEN'] = token;
  final appId = (env['META_OTA_APP_ID'] ?? yaml?.appId ?? '').trim();
  if (appId.isNotEmpty) {
    cliEnv['META_OTA_APP_ID'] = appId;
  }

  final sw = Stopwatch()..start();
  final ProcessRunnerResult result;
  try {
    result = await ProcessRunner(environment: cliEnv).runProcess(
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
