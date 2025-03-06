import 'package:args/command_runner.dart';

class ApkCommand extends Command {
  @override
  String get description => '打包Android的apk';

  @override
  String get name => 'apk';
}
