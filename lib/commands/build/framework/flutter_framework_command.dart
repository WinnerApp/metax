import 'package:args/command_runner.dart';

class FlutterFrameworkCommand extends Command {
  @override
  String get description => '编译Flutter Framework';

  @override
  String get name => 'flutter';
}
