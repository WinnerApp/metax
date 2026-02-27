import 'package:args/command_runner.dart';

import 'first_package_download_command.dart';
import 'first_package_init_command.dart';
import 'first_package_upload_command.dart';

class FirstPackageCommand extends Command {
  @override
  String get name => 'first_package';

  @override
  String get description => '首包相关操作';

  FirstPackageCommand() {
    addSubcommand(FirstPackageInitCommand());
    addSubcommand(FirstPackageUploadCommand());
    addSubcommand(FirstPackageDownloadCommand());
  }
}

