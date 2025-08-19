class FlutterWebVersionData {
  final String name;
  final String branch;
  final int version;
  final int gitVersion;
  FlutterWebVersionData({
    required this.name,
    required this.branch,
    required this.version,
    required this.gitVersion,
  });
  factory FlutterWebVersionData.fromJson(Map<String, dynamic> json) {
    return FlutterWebVersionData(
      name: json['name'],
      branch: json['branch'],
      version: json['version'],
      gitVersion: json['git_version'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'branch': branch,
      'version': version,
      'git_version': gitVersion,
    };
  }
}
