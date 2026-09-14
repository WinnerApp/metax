import 'package:args/command_runner.dart';
import 'package:meta_tool/commands/check_ota/check_ota_command.dart';
import 'package:meta_tool/commands/patch/patch_android_command.dart';
import 'package:test/test.dart';

void main() {
  test('check-ota accepts Jenkins --platform and --buildName', () {
    final runner = CommandRunner('metax', '')..addCommand(CheckOtaCommand());
    final result = runner.parse([
      'check-ota',
      '--platform',
      'android',
      '--buildName',
      '3.4.100',
    ]);
    expect(result.command?.name, 'check-ota');
    expect(result.command!['platform'], 'android');
    expect(result.command!['buildName'], '3.4.100');
  });

  test('patch android still accepts deprecated --channel', () {
    final cmd = PatchAndroidCommand();
    final result = cmd.argParser.parse(['--channel', 'stable']);
    expect(result['channel'], 'stable');
  });
}
