import 'package:args/command_runner.dart';
import 'package:meta_tool/commands/download/download_cache_command.dart';

class DownloadCommand extends Command {
  @override
  String get name => 'download';

  @override
  String get description => '下载';

  DownloadCommand() {
    addSubcommand(DownloadCacheCommand());
  }
}
