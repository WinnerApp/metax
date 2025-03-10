import 'package:meta_tool/cache/metax_cache.dart';
import 'package:meta_tool/define.dart';
import 'package:path/path.dart';

class FrameworkAarCache extends MetaxCache {
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
}
