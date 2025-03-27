import 'package:args/command_runner.dart';
import 'package:meta_tool/commands/upload/build_upload_apk_command.dart';
import 'package:meta_tool/commands/upload/build_upload_ipa_command.dart';
import 'package:meta_tool/commands/upload/upload_apk_command.dart';
import 'package:meta_tool/commands/upload/upload_ipa_command.dart';

class UploadCommand extends Command {
  @override
  String get name => 'upload';

  @override
  String get description => '上传安装包和资源文件';

  UploadCommand() {
    addSubcommand(UploadIpaCommand());
    addSubcommand(UploadApkCommand());
    addSubcommand(BuildUploadIpaCommand());
    addSubcommand(BuildUploadApkCommand());
  }
}
