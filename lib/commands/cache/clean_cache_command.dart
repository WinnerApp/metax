import 'dart:async';

import 'package:args/command_runner.dart';
import 'package:meta_tool/cache/cache_cleaner.dart';
import 'package:meta_tool/define.dart';

class CleanCacheCommand extends Command {
  @override
  String get description => '清理本地工程产物与 ~/.metax 缓存';

  @override
  String get name => 'clean';

  CleanCacheCommand() {
    addSubcommand(CleanFlutterCacheCommand());
    addSubcommand(CleanUnityCacheCommand());
    addSubcommand(CleanAllCacheCommand());
  }
}

class CleanFlutterCacheCommand extends Command {
  @override
  String get description =>
      '清理 Flutter 工程产物、宿主侧产物及 ~/.metax/flutter 缓存';

  @override
  String get name => 'flutter';

  @override
  FutureOr? run() {
    return cleanLibraryCaches(
      appHomeDir: appHomeDir,
      library: BuildLibrary.flutter,
    );
  }
}

class CleanUnityCacheCommand extends Command {
  @override
  String get description =>
      '清理 Unity 宿主侧产物及 ~/.metax/unity 缓存';

  @override
  String get name => 'unity';

  @override
  FutureOr? run() {
    return cleanLibraryCaches(
      appHomeDir: appHomeDir,
      library: BuildLibrary.unity,
    );
  }
}

class CleanAllCacheCommand extends Command {
  @override
  String get description => '清理 Flutter 与 Unity 的全部工程产物及 ~/.metax 缓存';

  @override
  String get name => 'all';

  @override
  FutureOr? run() {
    return cleanAllLibraryCaches(appHomeDir: appHomeDir);
  }
}
