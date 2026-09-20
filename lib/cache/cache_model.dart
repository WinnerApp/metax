import 'package:darty_json_safe/darty_json_safe.dart';

/// 解析 zip 缓存上的 `isShorebird`：空 / 缺失 / false → 非 Shorebird/FlutterPatch 产物。
bool parseCacheIsShorebird(dynamic value) {
  if (value == null) return false;
  if (value is bool) return value;
  final text = value.toString().trim().toLowerCase();
  if (text.isEmpty) return false;
  if (text == 'true' || text == '1' || text == 'yes') return true;
  return false;
}

/// Appwrite 同步 [contentHash] / [sourcePatchNumber]（及 zip 内
/// `.metax_artifact.json` sidecar），换机下载后写回本地 `cache.json`，
/// 供 by-artifact-hash promote。
enum CacheArtifactKind {
  /// 当前使用的本地槽（release / patch 全量包都写这里）
  release,

  /// 历史兼容：旧 patched 槽；新流程不再写入
  patched,
}

CacheArtifactKind parseCacheArtifactKind(dynamic value) {
  final text = value?.toString().trim().toLowerCase() ?? '';
  if (text == CacheArtifactKind.patched.name) {
    return CacheArtifactKind.patched;
  }
  // 缺失 / 非法值一律按 release，兼容旧缓存
  return CacheArtifactKind.release;
}

class CacheModel {
  final String buildPlatform;
  final String buildLibrary;
  final String buildType;
  final String branch;
  final String configuration;
  final String commitHash;
  final String buildId;
  final DateTime commitTime;

  /// Flutter SDK 指纹；Unity 等非 Flutter 产物为空字符串
  final String flutterSdk;

  /// 是否由 FlutterPatch（Shorebird fork）编译；空或 false 表示不是
  final bool isShorebird;

  /// 写入缓存时登记到 FlutterPatch 的 `--release-version`（如 `1.2.3+456`）。
  ///
  /// **不参与缓存命中比对**：同一 Flutter commit 可被多个宿主版本复用；
  /// 命中后用该字段做 `flutterpatch release --from-release`。
  final String releaseVersion;

  /// 本地文件名后缀；Appwrite 不分槽。参与本地命中比对（兼容旧 patched zip）。
  final CacheArtifactKind artifactKind;

  /// aar/xcframework 二进制 SHA-256；用于控制面 by-hash / `--from-release`。
  /// **不参与**命中比对；也不写入 Appwrite。
  final String contentHash;

  /// 补丁全量包对应的 FlutterPatch patch 号（可选元数据）；正式 release 为 null。
  ///
  /// **不参与**命中比对，也**不**决定 promote 路径；promote 以 [contentHash]
  /// 控制面 by-hash 的 `origin` 为准，本字段仅作一致性校验。
  final int? sourcePatchNumber;

  CacheModel({
    required this.buildPlatform,
    required this.buildLibrary,
    required this.buildType,
    required this.branch,
    required this.configuration,
    required this.commitHash,
    required this.buildId,
    required this.commitTime,
    this.flutterSdk = '',
    this.isShorebird = false,
    this.releaseVersion = '',
    this.artifactKind = CacheArtifactKind.release,
    this.contentHash = '',
    this.sourcePatchNumber,
  });

  CacheModel copyWith({
    String? buildPlatform,
    String? buildLibrary,
    String? buildType,
    String? branch,
    String? configuration,
    String? commitHash,
    String? buildId,
    DateTime? commitTime,
    String? flutterSdk,
    bool? isShorebird,
    String? releaseVersion,
    CacheArtifactKind? artifactKind,
    String? contentHash,
    int? sourcePatchNumber,
    bool clearSourcePatchNumber = false,
  }) {
    return CacheModel(
      buildPlatform: buildPlatform ?? this.buildPlatform,
      buildLibrary: buildLibrary ?? this.buildLibrary,
      buildType: buildType ?? this.buildType,
      branch: branch ?? this.branch,
      configuration: configuration ?? this.configuration,
      commitHash: commitHash ?? this.commitHash,
      buildId: buildId ?? this.buildId,
      commitTime: commitTime ?? this.commitTime,
      flutterSdk: flutterSdk ?? this.flutterSdk,
      isShorebird: isShorebird ?? this.isShorebird,
      releaseVersion: releaseVersion ?? this.releaseVersion,
      artifactKind: artifactKind ?? this.artifactKind,
      contentHash: contentHash ?? this.contentHash,
      sourcePatchNumber: clearSourcePatchNumber
          ? null
          : (sourcePatchNumber ?? this.sourcePatchNumber),
    );
  }

  factory CacheModel.fromJson(Map<String, dynamic> map) {
    final json = JSON(map);
    return CacheModel(
      buildPlatform: json['buildPlatform'].stringValue,
      buildLibrary: json['buildLibrary'].stringValue,
      buildType: json['buildType'].stringValue,
      branch: json['branch'].stringValue,
      configuration: json['configuration'].stringValue,
      commitHash: json['commitHash'].stringValue,
      buildId: json['buildId'].stringValue,
      commitTime: DateTime.parse(json['commitTime'].stringValue),
      flutterSdk: json['flutterSdk'].stringValue,
      isShorebird: parseCacheIsShorebird(
        map.containsKey('isShorebird') ? map['isShorebird'] : null,
      ),
      releaseVersion: json['releaseVersion'].stringValue,
      artifactKind: parseCacheArtifactKind(
        map.containsKey('artifactKind') ? map['artifactKind'] : null,
      ),
      contentHash: json['contentHash'].stringValue,
      sourcePatchNumber: () {
        final raw = map.containsKey('sourcePatchNumber')
            ? map['sourcePatchNumber']
            : map['source_patch_number'];
        if (raw == null) return null;
        if (raw is int) return raw;
        return int.tryParse(raw.toString().trim());
      }(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'branch': branch,
      'configuration': configuration,
      'commitHash': commitHash,
      'buildId': buildId,
      'buildPlatform': buildPlatform,
      'buildLibrary': buildLibrary,
      'buildType': buildType,
      'commitTime': commitTime.toUtc().toIso8601String(),
      'flutterSdk': flutterSdk,
      'isShorebird': isShorebird,
      'releaseVersion': releaseVersion,
      'artifactKind': artifactKind.name,
      'contentHash': contentHash,
      if (sourcePatchNumber != null) 'sourcePatchNumber': sourcePatchNumber,
    };
  }

  @override
  bool operator ==(Object other) {
    if (other is! CacheModel) return false;
    return branch == other.branch &&
        configuration == other.configuration &&
        commitHash == other.commitHash &&
        buildId == other.buildId &&
        buildPlatform == other.buildPlatform &&
        buildLibrary == other.buildLibrary &&
        buildType == other.buildType &&
        flutterSdk == other.flutterSdk &&
        isShorebird == other.isShorebird &&
        artifactKind == other.artifactKind;
  }

  @override
  int get hashCode => Object.hash(
        branch,
        configuration,
        commitHash,
        buildId,
        buildPlatform,
        buildLibrary,
        buildType,
        flutterSdk,
        isShorebird,
        artifactKind,
      );
}

class ServerCacheModel extends CacheModel {
  final String fileId;

  ServerCacheModel({
    required this.fileId,
    required super.buildPlatform,
    required super.buildLibrary,
    required super.buildType,
    required super.branch,
    required super.configuration,
    required super.commitHash,
    required super.buildId,
    required super.commitTime,
    super.flutterSdk,
    super.isShorebird,
    super.releaseVersion,
    super.artifactKind,
    super.contentHash,
    super.sourcePatchNumber,
  });

  factory ServerCacheModel.fromJson(Map<String, dynamic> map) {
    final json = JSON(map);
    return ServerCacheModel(
      fileId: json['file_id'].stringValue,
      buildPlatform: json['platform'].stringValue,
      buildLibrary: json['library'].stringValue,
      buildType: json['type'].stringValue,
      branch: json['branch'].stringValue,
      configuration: json['configuration'].stringValue,
      commitHash: json['commit_hash'].stringValue,
      buildId: json['build_id'].stringValue,
      commitTime: DateTime.parse(json['commit_time'].stringValue),
      flutterSdk: json['flutter_sdk'].stringValue,
      isShorebird: parseCacheIsShorebird(
        map.containsKey('isShorebird') ? map['isShorebird'] : null,
      ),
      releaseVersion: _readReleaseVersion(map),
      artifactKind: parseCacheArtifactKind(
        map.containsKey('artifactKind')
            ? map['artifactKind']
            : map['artifact_kind'],
      ),
      contentHash: () {
        final camel = map['contentHash']?.toString().trim() ?? '';
        if (camel.isNotEmpty) return camel;
        return map['content_hash']?.toString().trim() ?? '';
      }(),
      sourcePatchNumber: () {
        final raw = map.containsKey('sourcePatchNumber')
            ? map['sourcePatchNumber']
            : map['source_patch_number'];
        if (raw == null) return null;
        if (raw is int) return raw;
        return int.tryParse(raw.toString().trim());
      }(),
    );
  }
}

String _readReleaseVersion(Map<String, dynamic> map) {
  final camel = map['releaseVersion']?.toString().trim() ?? '';
  if (camel.isNotEmpty) return camel;
  return map['release_version']?.toString().trim() ?? '';
}
