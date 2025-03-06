import 'package:args/command_runner.dart';

class AppCommand extends Command {
  @override
  String get description => '打包iOS和Android的安装包';

  @override
  String get name => 'app';
}
