import 'package:args/command_runner.dart';

class UnityFrameworkCommand extends Command {
  @override
  String get description => '打包Unity Framework';

  @override
  String get name => 'unity';
}
