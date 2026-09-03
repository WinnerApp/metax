import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:meta_tool/app_home_dir.dart';
import 'package:meta_tool/common.dart';
import 'package:meta_tool/shorebird.dart';
import 'package:path/path.dart';

class MetaOtaConfig {
  final String api;
  final String token;
  final String? appId;
  final String arch;
  final String channel;

  const MetaOtaConfig({
    required this.api,
    required this.token,
    this.appId,
    this.arch = 'aarch64',
    this.channel = 'stable',
  });

  factory MetaOtaConfig.fromEnv({
    ShorebirdYamlConfig? yaml,
    Map<String, String>? environment,
  }) {
    final env = environment ?? Platform.environment;
    final api = (env['META_OTA_API'] ?? yaml?.baseUrl ?? '').trim();
    final token = (env['META_OTA_TOKEN'] ?? '').trim();
    final appId = (env['META_OTA_APP_ID'] ?? yaml?.appId ?? '').trim();
    final arch = (env['META_OTA_ARCH'] ?? 'aarch64').trim();
    final channel = (env['META_OTA_CHANNEL'] ?? 'stable').trim();
    if (api.isEmpty) {
      throw Exception(
        '缺少 META_OTA_API（或 shorebird.yaml base_url）。补丁需推送到 Meta Code Push。',
      );
    }
    if (token.isEmpty) {
      throw Exception('缺少 META_OTA_TOKEN（Meta OTA Admin / API Key）。');
    }
    return MetaOtaConfig(
      api: api.replaceAll(RegExp(r'/$'), ''),
      token: token,
      appId: appId.isEmpty ? null : appId,
      arch: arch,
      channel: channel,
    );
  }
}

class MetaOtaPatchUploadResult {
  final String patchId;
  final String rawCreateResponse;
  final String? checkResponse;

  const MetaOtaPatchUploadResult({
    required this.patchId,
    required this.rawCreateResponse,
    this.checkResponse,
  });
}

class MetaOtaClient {
  MetaOtaClient(this.config) : _dio = Dio(BaseOptions(
          baseUrl: config.api,
          headers: {
            'content-type': 'application/json',
            'authorization': 'Bearer ${config.token}',
          },
          connectTimeout: const Duration(seconds: 60),
          receiveTimeout: const Duration(minutes: 5),
          sendTimeout: const Duration(minutes: 5),
        ));

  final MetaOtaConfig config;
  final Dio _dio;

  Future<Map<String, dynamic>> uploadPatch({
    required String appId,
    required String releaseVersion,
    required String platform,
    required String arch,
    required File diffFile,
    required String patchedBinaryHash,
    String channel = 'staging',
    int rolloutPercent = 100,
    String? notes,
  }) async {
    if (!diffFile.existsSync()) {
      throw Exception('patch diff 不存在: ${diffFile.path}');
    }
    final bytes = await diffFile.readAsBytes();
    if (bytes.length < 32) {
      throw Exception('patch diff 过小 (${bytes.length} bytes)，不是有效 Shorebird diff');
    }
    final body = <String, dynamic>{
      'app_id': appId,
      'release_version': releaseVersion,
      'platform': platform,
      'arch': arch,
      'channel': channel,
      'rollout_percent': rolloutPercent,
      'content_base64': base64Encode(bytes),
      'hash': patchedBinaryHash,
      if (notes != null) 'notes': notes,
    };
    final res = await _dio.post('/admin/v1/patches', data: body);
    final data = res.data;
    if (data is Map<String, dynamic>) return data;
    if (data is String) {
      return jsonDecode(data) as Map<String, dynamic>;
    }
    throw Exception('Meta OTA 上传返回无法解析: $data');
  }

  Future<void> promotePatch({
    required String patchId,
    required String channel,
  }) async {
    await _dio.post('/admin/v1/patches/$patchId/promote', data: {
      'channel': channel,
    });
  }

  Future<String> checkPatch({
    required String appId,
    required String releaseVersion,
    required String platform,
    required String arch,
    required String channel,
  }) async {
    final res = await _dio.post(
      '/api/v1/patches/check',
      data: {
        'app_id': appId,
        'channel': channel,
        'release_version': releaseVersion,
        'platform': platform,
        'arch': arch,
        'client_id': 'metax-verify',
      },
      options: Options(headers: {'content-type': 'application/json'}),
    );
    return const JsonEncoder.withIndent('  ').convert(res.data);
  }
}

class ShorebirdPatchArtifacts {
  final File diffFile;
  final String patchedBinaryHash;
  final File? patchedBinary;

  const ShorebirdPatchArtifacts({
    required this.diffFile,
    required this.patchedBinaryHash,
    this.patchedBinary,
  });
}

/// 定位 shorebird patch 后的 diff 与 patched 二进制 hash（add-to-app 路径）
Future<ShorebirdPatchArtifacts> locateShorebirdPatchArtifacts({
  required AppHomeDir appHomeDir,
  required String platform, // android | ios
  String arch = 'aarch64',
  Map<String, String>? environment,
}) async {
  final env = environment ?? Platform.environment;
  final flutterDir = appHomeDir.flutterDir;

  File? patchedBinary;
  final envPatched = (env['META_OTA_PATCH_LIBAPP'] ?? '').trim();
  if (envPatched.isNotEmpty && File(envPatched).existsSync()) {
    patchedBinary = File(envPatched);
  } else if (platform == 'android') {
    final abi = switch (arch) {
      'aarch64' || 'arm64' => 'arm64-v8a',
      'x86_64' => 'x86_64',
      'arm' => 'armeabi-v7a',
      _ => arch,
    };
    final candidates = [
      join(
        flutterDir.path,
        'build',
        'host',
        'outputs',
        'native-debug-symbols',
        // fallback paths below
      ),
      // module / aar 常见路径
      join(flutterDir.path, 'build', 'out', 'libapp.so'),
      // sample_app 风格（纯 app）
      join(
        flutterDir.path,
        'build',
        'app',
        'intermediates',
        'stripped_native_libs',
        'release',
        'stripReleaseDebugSymbols',
        'out',
        'lib',
        abi,
        'libapp.so',
      ),
    ];
    for (final path in candidates) {
      final f = File(path);
      if (f.existsSync()) {
        patchedBinary = f;
        break;
      }
    }
    // 在 flutterDir/build 下搜 libapp.so
    patchedBinary ??= await _findNewestFile(
      flutterDir,
      name: 'libapp.so',
      minSize: 1024,
      maxAgeMinutes: 180,
    );
  } else if (platform == 'ios') {
    final vmcode = File(join(flutterDir.path, 'build', 'out.vmcode'));
    if (vmcode.existsSync()) {
      patchedBinary = vmcode;
    } else {
      patchedBinary = await _findNewestFile(
        flutterDir,
        name: 'out.vmcode',
        minSize: 1024,
        maxAgeMinutes: 180,
      );
      if (patchedBinary == null) {
        final appBinary = File(join(
          flutterDir.path,
          'build',
          'ios',
          'framework',
          'Release',
          'App.xcframework',
          'ios-arm64',
          'App.framework',
          'App',
        ));
        if (appBinary.existsSync()) {
          patchedBinary = appBinary;
        }
      }
    }
  }

  var hash = (env['META_OTA_LIBAPP_HASH'] ?? '').trim();
  if (hash.isEmpty) {
    if (patchedBinary == null || !patchedBinary.existsSync()) {
      throw Exception(
        '无法定位 patched 二进制以计算 hash。'
        '请设置 META_OTA_LIBAPP_HASH 或 META_OTA_PATCH_LIBAPP。',
      );
    }
    hash = sha256.convert(await patchedBinary.readAsBytes()).toString();
  }

  final envDiff = (env['META_OTA_PATCH_FILE'] ?? '').trim();
  File? diffFile;
  if (envDiff.isNotEmpty && File(envDiff).existsSync()) {
    diffFile = File(envDiff);
  } else {
    diffFile = await _findRecentDiffPatch(patchedBinary);
  }

  if (diffFile == null || !diffFile.existsSync()) {
    throw Exception(
      '未找到 Shorebird diff.patch。'
      '请在 shorebird patch 后立即运行，或设置 META_OTA_PATCH_FILE。',
    );
  }

  return ShorebirdPatchArtifacts(
    diffFile: diffFile,
    patchedBinaryHash: hash,
    patchedBinary: patchedBinary,
  );
}

Future<MetaOtaPatchUploadResult> uploadShorebirdPatchToMetaOta({
  required AppHomeDir appHomeDir,
  required String platform, // android | ios
  required String releaseVersion,
  String? channel,
  bool promote = true,
  bool verifyCheck = true,
  Map<String, String>? environment,
}) async {
  final yaml = ShorebirdYamlConfig.tryLoad(appHomeDir.flutterDir);
  final config = MetaOtaConfig.fromEnv(yaml: yaml, environment: environment);
  final appId = config.appId;
  if (appId == null || appId.isEmpty) {
    throw Exception('缺少 app_id（META_OTA_APP_ID 或 shorebird.yaml）');
  }

  final artifacts = await locateShorebirdPatchArtifacts(
    appHomeDir: appHomeDir,
    platform: platform,
    arch: config.arch,
    environment: environment,
  );

  loggerInfo(
    'Meta OTA 上传: api=${config.api} app=$appId '
    'version=$releaseVersion platform=$platform '
    'diff=${artifacts.diffFile.path} hash=${artifacts.patchedBinaryHash}',
  );

  final client = MetaOtaClient(config);
  final createBody = await client.uploadPatch(
    appId: appId,
    releaseVersion: releaseVersion,
    platform: platform,
    arch: config.arch,
    diffFile: artifacts.diffFile,
    patchedBinaryHash: artifacts.patchedBinaryHash,
    channel: 'staging',
    notes: 'uploaded by metax',
  );

  final patchId = createBody['id']?.toString();
  if (patchId == null || patchId.isEmpty) {
    throw Exception('Meta OTA 未返回 patch id: $createBody');
  }

  final promoteChannel = channel ?? config.channel;
  if (promote) {
    loggerInfo('Meta OTA promote → $promoteChannel (id=$patchId)');
    await client.promotePatch(patchId: patchId, channel: promoteChannel);
  }

  String? checkResponse;
  if (verifyCheck) {
    try {
      checkResponse = await client.checkPatch(
        appId: appId,
        releaseVersion: releaseVersion,
        platform: platform,
        arch: config.arch,
        channel: promoteChannel,
      );
      loggerInfo('Meta OTA check:\n$checkResponse');
    } catch (e) {
      loggerWarning('Meta OTA check 校验失败（补丁可能已上传）: $e');
    }
  }

  return MetaOtaPatchUploadResult(
    patchId: patchId,
    rawCreateResponse: const JsonEncoder.withIndent('  ').convert(createBody),
    checkResponse: checkResponse,
  );
}

Future<File?> _findRecentDiffPatch(File? anchor) async {
  final tmp = Platform.environment['TMPDIR'] ?? '/tmp';
  final roots = <Directory>[
    Directory(tmp),
    Directory('/var/folders'),
  ];
  final anchorM =
      anchor != null && anchor.existsSync() ? await anchor.lastModified() : null;

  File? newest;
  DateTime? newestM;
  for (final root in roots) {
    if (!root.existsSync()) continue;
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      if (basename(entity.path) != 'diff.patch') continue;
      try {
        final stat = await entity.stat();
        if (stat.size < 1024) continue;
        final m = stat.modified;
        if (anchorM != null) {
          final delta = m.difference(anchorM).inSeconds.abs();
          if (delta > 900) continue;
        } else {
          if (DateTime.now().difference(m).inMinutes > 180) continue;
        }
        if (newestM == null || m.isAfter(newestM)) {
          newestM = m;
          newest = entity;
        }
      } catch (_) {
        continue;
      }
    }
  }
  return newest;
}

Future<File?> _findNewestFile(
  Directory root, {
  required String name,
  required int minSize,
  required int maxAgeMinutes,
}) async {
  if (!root.existsSync()) return null;
  File? newest;
  DateTime? newestM;
  final cutoff = DateTime.now().subtract(Duration(minutes: maxAgeMinutes));
  await for (final entity in root.list(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    if (basename(entity.path) != name) continue;
    try {
      final stat = await entity.stat();
      if (stat.size < minSize) continue;
      if (stat.modified.isBefore(cutoff)) continue;
      if (newestM == null || stat.modified.isAfter(newestM)) {
        newestM = stat.modified;
        newest = entity;
      }
    } catch (_) {
      continue;
    }
  }
  return newest;
}
