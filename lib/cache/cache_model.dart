import 'package:darty_json_safe/darty_json_safe.dart';

/// 解析 zip 缓存上的 `isShorebird`：空 / 缺失 / false → 非 Shorebird。
bool parseCacheIsShorebird(dynamic value) {
  if (value == null) return false;
  if (value is bool) return value;
  final text = value.toString().trim().toLowerCase();
  if (text.isEmpty) return false;
  if (text == 'true' || text == '1' || text == 'yes') return true;
  return false;
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

  /// 是否由 Shorebird / FlutterPatch 编译；空或 false 表示不是
  final bool isShorebird;

  /// 写入缓存时登记到 FlutterPatch 的 `--release-version`（如 `1.2.3+456`）。
  ///
  /// **不参与缓存命中比对**：同一 Flutter commit 可被多个宿主版本复用；
  /// 命中后用该字段做 `flutterpatch release --from-release`。
  final String releaseVersion;

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
        isShorebird == other.isShorebird;
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
    );
  }
}

String _readReleaseVersion(Map<String, dynamic> map) {
  final camel = map['releaseVersion']?.toString().trim() ?? '';
  if (camel.isNotEmpty) return camel;
  return map['release_version']?.toString().trim() ?? '';
}
