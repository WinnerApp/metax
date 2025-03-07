import 'package:darty_json_safe/darty_json_safe.dart';
import 'package:meta_tool/cache/cache.dart';
import 'package:meta_tool/define.dart';
import 'package:path/path.dart';

class FrameworkAarCache extends Cache {
  final BuildPlatform platform;
  final BuildConfiguration configuration;
  final BuildType type;
  final BuildLibrary library;

  FrameworkAarCache({
    required this.platform,
    required this.configuration,
    required this.type,
    required this.library,
  });

  @override
  String get cacheHome => join(
        super.cacheHome,
        type.value,
        platform.value,
        library.value,
        configuration.value,
      );

  @override
  Future<String?> getBranchLatestCommitHash(String branch) async {
    final ids = await getIdsFromBranch(branch);
    return ids.isEmpty ? null : ids.last;
  }

  @override
  Map<String, dynamic> updateCacheData(
    Map<String, dynamic> cacheData,
    String branch,
    String commitHash,
  ) {
    List<String> ids = [
      ...JSON(cacheData)[branch].listValue.map((e) => e.toString())
    ];
    ids.add(commitHash);
    cacheData[branch] = ids;
    return cacheData;
  }

  Future<List<String>> getIdsFromBranch(String branch) async {
    final json = JSON(await getCacheData(branch));
    return json[branch].listValue.map((e) => e.toString()).toList();
  }
}
