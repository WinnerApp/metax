import 'package:meta_tool/cache/cache.dart';
import 'package:meta_tool/common.dart';
import 'package:path/path.dart';

abstract class MetaxCache extends Cache {
  @override
  String get cacheHome => join(readEnv('HOME'), '.metax');

  @override
  String get cacheJsonPath => join(cacheHome, 'cache.json');
}
