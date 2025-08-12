import 'package:args/command_runner.dart';

class FlutterWebCacheCommand extends Command {
  @override
  String get name => 'flutter_web_cache';
  @override
  String get description => 'flutter web cache';

  FlutterWebCacheCommand() {
    // Add any options or arguments here if needed
    argParser.addOption('version', help: '热更资源的版本');
    argParser.addFlag('enable', help: '是否开启热更');
    argParser.addOption('routeName', help: '路由名称');
  }

  @override
  Future<void> run() async {}
}
