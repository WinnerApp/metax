import 'package:args/command_runner.dart';

class IpaCommand extends Command {
  @override
  String get description => '打包iOS的ipa安装包';

  @override
  String get name => 'ipa';
}
