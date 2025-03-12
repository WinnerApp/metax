import 'package:meta_tool/cache/cache.dart';
import 'package:meta_tool/cache/cache_manager.dart';

class BuildCache extends Cache {
  final String buildCacheDir;
  BuildCache(this.buildCacheDir) : super(BuildCacheManager(buildCacheDir));
}
