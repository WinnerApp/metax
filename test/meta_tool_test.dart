import 'package:meta_tool/cache/metax_cache.dart';
import 'package:meta_tool/define.dart';
import 'package:test/scaffolding.dart';

void main() {
  test('测试本地数据', () async {
    final metaxCache = MetaxCache(
      buildPlatform: BuildPlatform.ios,
      buildConfiguration: BuildConfiguration.release,
      buildLibrary: BuildLibrary.unity,
      buildType: BuildType.library,
      branch: '1.5.0',
      buildId: 0,
    );
    final cacheModels = await metaxCache.cacheManager.read();
    print(cacheModels);
  });
}
