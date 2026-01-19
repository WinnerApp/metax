import 'package:darty_json_safe/darty_json_safe.dart';

class CacheModel {
  final String buildPlatform;
  final String buildLibrary;
  final String buildType;
  final String branch;
  final String configuration;
  final String commitHash;
  final String buildId;
  final DateTime commitTime;

  CacheModel({
    required this.buildPlatform,
    required this.buildLibrary,
    required this.buildType,
    required this.branch,
    required this.configuration,
    required this.commitHash,
    required this.buildId,
    required this.commitTime,
  });

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
        buildType == other.buildType;
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
  });

  factory ServerCacheModel.fromJson(Map<String, dynamic> map) {
    final json = JSON(map);
    // 从 build_platform 字段读取，如果为 null 则默认为 'macos'
    // 注意：'platform' 字段是构建目标平台（ios/android），而 'build_platform' 是构建所在平台（macos/windows）
    final buildPlatformValue = json['build_platform'].stringValue;
    final buildPlatform = buildPlatformValue.isEmpty ? 'macos' : buildPlatformValue;
    return ServerCacheModel(
      fileId: json['file_id'].stringValue,
      buildPlatform: buildPlatform,
      buildLibrary: json['library'].stringValue,
      buildType: json['type'].stringValue,
      branch: json['branch'].stringValue,
      configuration: json['configuration'].stringValue,
      commitHash: json['commit_hash'].stringValue,
      buildId: json['build_id'].stringValue,
      commitTime: DateTime.parse(json['commit_time'].stringValue),
    );
  }
}
