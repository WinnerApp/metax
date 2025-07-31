import 'package:args/command_runner.dart';
import 'package:meta_tool/commands/test/test_send_msg_command.dart';

class TestCommand extends Command {
  @override
  String get name => 'test';

  @override
  String get description => '测试';

  TestCommand() {
    addSubcommand(TestSendMsgCommand());
  }
}
