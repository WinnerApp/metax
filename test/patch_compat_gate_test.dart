import 'package:meta_tool/commands/patch/patch_compat_gate.dart';
import 'package:meta_tool/shorebird.dart';
import 'package:test/test.dart';

void main() {
  group('parseShorebirdReleaseVersion', () {
    test('splits name and number', () {
      final parsed = parseShorebirdReleaseVersion('1.2.3+456');
      expect(parsed.buildName, '1.2.3');
      expect(parsed.buildNumber, '456');
    });

    test('rejects missing plus', () {
      expect(() => parseShorebirdReleaseVersion('1.2.3'), throwsArgumentError);
    });
  });

  group('PatchCompatGate.classifyPath', () {
    test('allows dart sources', () {
      expect(PatchCompatGate.classifyPath('lib/main.dart'), isNull);
      expect(
        PatchCompatGate.classifyPath(
          'lib/main.dart',
          pathPrefix: 'metaapp_flutter',
        ),
        isNull,
      );
    });

    test('blocks native under submodule and host', () {
      expect(
        PatchCompatGate.classifyPath('android/src/foo.java'),
        '宿主原生工程',
      );
      expect(
        PatchCompatGate.classifyPath(
          'ios/Classes/Plugin.m',
          pathPrefix: 'packages/foo',
        ),
        '宿主原生工程',
      );
      expect(
        PatchCompatGate.classifyPath('ios/Runner/AppDelegate.swift'),
        '宿主原生工程',
      );
    });

    test('blocks assets and marks unity repo', () {
      expect(
        PatchCompatGate.classifyPath('assets/images/a.png'),
        '资源文件',
      );
      expect(
        PatchCompatGate.classifyPath('anything.dart', isUnity: true),
        'Unity 相关',
      );
    });

    test('allows yaml/json in flutter modules', () {
      expect(PatchCompatGate.classifyPath('pubspec.yaml'), isNull);
      expect(PatchCompatGate.classifyPath('config/foo.json'), isNull);
    });
  });
}
