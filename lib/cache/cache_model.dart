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

  /// Flutter SDK 指纹；Unity 等非 Flutter 产物为空字符串
  final String flutterSdk;

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
      flutterSdk: json['flutterSdk'].stringValue,
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
        flutterSdk == other.flutterSdk;
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
    );
  }
}
