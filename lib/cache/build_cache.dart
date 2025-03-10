import 'package:meta_tool/cache/cache.dart';
import 'package:path/path.dart';

class BuildCache extends Cache {
  final String buildCacheDir;

  BuildCache({required this.buildCacheDir});

  @override
  String get cacheHome => buildCacheDir;

  @override
  String get cacheJsonPath => join(cacheHome, '.build_id');
}
