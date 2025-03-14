import 'package:args/command_runner.dart';
import 'package:meta_tool/commands/cache/download_cache_command.dart';
import 'package:meta_tool/commands/cache/upload_cache_command.dart';
import 'package:meta_tool/commands/cache/use_cache_command.dart';

class CacheCommand extends Command {
  @override
  String get description => '缓存管理';

  @override
  String get name => 'cache';

  CacheCommand() {
    addSubcommand(DownloadCacheCommand());
    addSubcommand(UploadCacheCommand());
    addSubcommand(UseCacheCommand());
  }
}
