import 'package:darty_json_safe/darty_json_safe.dart';
import 'package:meta_tool/cache/metax_cache.dart';
import 'package:meta_tool/define.dart';
import 'package:path/path.dart';

class UnityCache extends MetaxCache {
  final BuildPlatform platform;

  UnityCache({required this.platform}) : super();

  @override
  String get cacheHome => join(super.cacheHome, 'unity', platform.name);

  /// 根据BuildVersionId查询最新的静态库的CommitHash
  ///
  /// [branch] 分支名称
  /// [buildVersionId] 构建版本ID
  Future<String?> getLatestCommitHash({
    required String branch,
    required int buildVersionId,
  }) async {
    final cacheDataList = await filterCacheDataList((data) {
      final json = JSON(data);
      final branchData = json[branch].string;
      final buildVersionIdData = json[buildVersionId].int;
      return (branchData == branch && buildVersionIdData == buildVersionId)
          ? data
          : null;
    });

    if (cacheDataList.isEmpty) {
      return null;
    }

    return cacheDataList.last['commitHash'].string;
  }
}
