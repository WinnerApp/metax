import 'package:darty_json_safe/darty_json_safe.dart';
import 'package:meta_tool/cache/cache.dart';
import 'package:meta_tool/define.dart';
import 'package:path/path.dart';

class UnityCache extends Cache {
  final BuildPlatform platform;

  UnityCache({required this.platform}) : super();

  @override
  String get cacheHome => join(super.cacheHome, 'unity', platform.name);

  /// 获取指定分支最新的缓存Commit Hash
  @override
  Future<String?> getBranchLatestCommitHash(String branch) async {
    final json = JSON(await getCacheData(branch));
    return json[branch].string;
  }

  @override
  Map<String, dynamic> updateCacheData(
    Map<String, dynamic> cacheData,
    String branch,
    String commitHash,
  ) {
    cacheData[branch] = commitHash;
    return cacheData;
  }
}
