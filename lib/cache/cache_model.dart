import 'package:darty_json_safe/darty_json_safe.dart';

class CacheModel {
  final String branch;
  final String configuration;
  final String commitHash;
  final String buildId;
  final bool isStore;

  CacheModel({
    required this.branch,
    required this.configuration,
    required this.commitHash,
    required this.buildId,
    required this.isStore,
  });

  factory CacheModel.fromJson(Map<String, dynamic> map) {
    final json = JSON(map);
    return CacheModel(
      branch: json['branch'].stringValue,
      configuration: json['configuration'].stringValue,
      commitHash: json['commitHash'].stringValue,
      buildId: json['buildId'].stringValue,
      isStore: json['isStore'].boolValue,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'branch': branch,
      'configuration': configuration,
      'commitHash': commitHash,
      'buildId': buildId,
      'isStore': isStore,
    };
  }

  @override
  bool operator ==(Object other) {
    if (other is! CacheModel) return false;
    return branch == other.branch &&
        configuration == other.configuration &&
        commitHash == other.commitHash &&
        buildId == other.buildId &&
        isStore == other.isStore;
  }

  @override
  int get hashCode => Object.hash(
        branch,
        configuration,
        commitHash,
        buildId,
        isStore,
      );
}
