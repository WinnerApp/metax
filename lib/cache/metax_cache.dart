import 'package:meta_tool/cache/cache.dart';
import 'package:meta_tool/cache/cache_manager.dart';
import 'package:meta_tool/common.dart';
import 'package:meta_tool/define.dart';
import 'package:path/path.dart';

class MetaxCache extends Cache {
  final BuildPlatform buildPlatform;
  final bool isStore;
  final BuildConfiguration buildConfiguration;
  final BuildLibrary buildLibrary;
  final BuildType buildType;
  final String branch;
  final int buildId;
  MetaxCache({
    required this.buildPlatform,
    required this.isStore,
    required this.buildConfiguration,
    required this.buildLibrary,
    required this.buildType,
    required this.branch,
    this.buildId = 0,
  }) : super(
          join(
            readEnv('HOME'),
            '.metax',
            buildPlatform.name,
            isStore ? 'store' : 'test',
            buildConfiguration.name,
            buildLibrary.name,
            buildType.name,
            branch,
            '$buildId',
          ),
          MetaxCacheManager(),
        );
}
