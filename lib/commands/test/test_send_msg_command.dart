import 'package:args/command_runner.dart';
import 'package:meta_tool/common.dart';

class TestSendMsgCommand extends Command {
  @override
  String get name => 'test-send-msg';

  @override
  String get description => '测试发送消息';

  TestSendMsgCommand() {
    argParser.addOption('msg', abbr: 'm', help: '消息内容');
    argParser.addOption('url', abbr: 'u', help: 'webhook url');
  }

  @override
  Future<void> run() async {
    final msg = argResults?['msg'] as String;
    final url = argResults?['url'] as String;
    if (msg.isEmpty) {
      throw '消息内容不能为空';
    }
    if (url.isEmpty) {
      throw 'webhook url不能为空';
    }
    await sendTextToWeixinWebhooks(
      msg,
      url,
    );
  }
}
