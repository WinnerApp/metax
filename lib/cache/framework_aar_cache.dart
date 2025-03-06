import 'dart:convert';
import 'dart:io';

import 'package:meta_tool/cache/cache.dart';
import 'package:path/path.dart';

class FrameworkAarCache extends Cache {
  final FrameworkAarPlatform platform;
  FrameworkAarCache(this.platform);

  @override
  String get cacheHome => join(super.cacheHome, platform.value);

  /// 查询当前分支最新commit hash
  Future<String?> getLatestCommitHashFromBranch(String branch) async {
    final jsonText =
        await File(cacheJsonPath).readAsString().catchError((e) => '{}');
    final json = jsonDecode(jsonText);
    final ids = json[branch];
    if (ids == null) {
      return null;
    }
    return ids.last;
  }

  /// 更新最新的commit hash
  Future<void> updateLatestCommitHash(String branch, String commitHash) async {
    final jsonText =
        await File(cacheJsonPath).readAsString().catchError((e) => '{}');
    final json = jsonDecode(jsonText);
    json[branch] = [commitHash];
  }
}

enum FrameworkAarPlatform {
  flutter('flutter'),
  unity('unity');

  final String value;
  const FrameworkAarPlatform(this.value);
}
