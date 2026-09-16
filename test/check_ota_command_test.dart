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

  test('check-ota accepts branch, release-version and out paths', () {
    final runner = CommandRunner('metax', '')..addCommand(CheckOtaCommand());
    final result = runner.parse([
      'check-ota',
      '--platform',
      'ios',
      '--release-version',
      '3.4.100+1788746134',
      '--branch',
      'development',
      '--unsupported-out',
      '/tmp/unsupported.json',
      '--supported-out',
      '/tmp/supported.json',
      '--resources-out',
      '/tmp/resources.json',
    ]);
    expect(result.command!['release-version'], '3.4.100+1788746134');
    expect(result.command!['branch'], 'development');
    expect(result.command!['unsupported-out'], '/tmp/unsupported.json');
    expect(result.command!['supported-out'], '/tmp/supported.json');
    expect(result.command!['resources-out'], '/tmp/resources.json');
  });

  test('patch android accepts whitelist, unique-ids and check-only', () {
    final cmd = PatchAndroidCommand();
    final result = cmd.argParser.parse([
      '--whitelist',
      '--unique-ids',
      'a,b',
      '--check-only',
      '--resources-out',
      '/tmp/resources.json',
    ]);
    expect(result['whitelist'], isTrue);
    expect(result['unique-ids'], ['a', 'b']);
    expect(result['check-only'], isTrue);
    expect(result['resources-out'], '/tmp/resources.json');
  });

  test('patch android still accepts deprecated --channel', () {
    final cmd = PatchAndroidCommand();
    final result = cmd.argParser.parse(['--channel', 'stable']);
    expect(result['channel'], 'stable');
  });
}
