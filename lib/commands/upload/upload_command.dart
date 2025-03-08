import 'package:args/command_runner.dart';
import 'package:meta_tool/commands/upload/upload_app_command.dart';

class UploadCommand extends Command {
  @override
  String get name => 'upload';

  @override
  String get description => '上传安装包和资源文件';

  UploadCommand() {
    addSubcommand(UploadAppCommand());
  }
}