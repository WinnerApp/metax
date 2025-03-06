import 'package:meta_tool/common.dart';
import 'package:path/path.dart';

abstract class Cache {
  String get cacheHome => join(readEnv('HOME'), '.metax');
  String get cacheJsonPath => join(cacheHome, 'cache.json');
}
