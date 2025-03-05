import 'package:args/command_runner.dart';

class InitCommand extends Command {
  @override
  String get description => '初始化一些操作，比如工程';

  @override
  String get name => 'init';
}
