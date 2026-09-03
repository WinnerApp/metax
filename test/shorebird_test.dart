import 'dart:io';

import 'package:meta_tool/app_home_dir.dart';
import 'package:meta_tool/commands/patch/patch_compat_gate.dart';
import 'package:meta_tool/shorebird.dart';
import 'package:path/path.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late AppHomeDir home;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('metax_shorebird_');
    Directory(join(tempDir.path, 'metaapp_flutter')).createSync();
    home = AppHomeDir(tempDir.path);
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  void writePubspec({required bool? shorebirdEnabled}) {
    final buffer = StringBuffer('name: demo\n');
    if (shorebirdEnabled != null) {
      buffer.writeln('metax:');
      buffer.writeln('  shorebird_enabled: $shorebirdEnabled');
    }
    File(join(home.flutterDir.path, 'pubspec.yaml')).writeAsStringSync(
      buffer.toString(),
    );
  }

  group('resolveUseShorebird', () {
    test('defaults off without pubspec field', () {
      writePubspec(shorebirdEnabled: null);
      File(join(home.flutterDir.path, 'shorebird.yaml')).writeAsStringSync('''
app_id: "abc"
base_url: http://ota.local
''');
      final r = resolveUseShorebird(appHomeDir: home, environment: {});
      expect(r.enabled, isFalse);
      expect(r.reason, contains('unset'));
    });

    test('pubspec metax.shorebird_enabled true enables', () {
      writePubspec(shorebirdEnabled: true);
      File(join(home.flutterDir.path, 'shorebird.yaml')).writeAsStringSync('''
app_id: "abc"
''');
      final r = resolveUseShorebird(appHomeDir: home, environment: {});
      expect(r.enabled, isTrue);
      expect(r.yaml?.appId, 'abc');
      expect(r.reason, contains('pubspec.yaml'));
    });

    test('file existence alone does not enable', () {
      writePubspec(shorebirdEnabled: false);
      File(join(home.flutterDir.path, 'shorebird.yaml')).writeAsStringSync('''
app_id: "abc"
''');
      final r = resolveUseShorebird(appHomeDir: home, environment: {});
      expect(r.enabled, isFalse);
    });

    test('CLI overrides pubspec', () {
      writePubspec(shorebirdEnabled: true);
      final off = resolveUseShorebird(
        appHomeDir: home,
        explicitUseShorebird: false,
        environment: {},
      );
      expect(off.enabled, isFalse);

      writePubspec(shorebirdEnabled: false);
      final on = resolveUseShorebird(
        appHomeDir: home,
        explicitUseShorebird: true,
        environment: {},
      );
      expect(on.enabled, isTrue);
    });

    test('env overrides pubspec', () {
      writePubspec(shorebirdEnabled: true);
      final r = resolveUseShorebird(
        appHomeDir: home,
        environment: {'SHOREBIRD_ENABLED': 'false'},
      );
      expect(r.enabled, isFalse);
    });

    test('top-level metax_enabled in pubspec', () {
      File(join(home.flutterDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: demo
metax_enabled: true
''');
      final r = resolveUseShorebird(appHomeDir: home, environment: {});
      expect(r.enabled, isTrue);
    });
  });

  group('buildShorebirdReleaseVersion', () {
    test('joins name and number', () {
      expect(
        buildShorebirdReleaseVersion(buildName: '1.2.3', buildNumber: '9'),
        '1.2.3+9',
      );
    });
  });

  group('shorebirdCliEnvironment', () {
    test('always forces official hosted URL and storage base', () {
      final env = shorebirdCliEnvironment({
        'SHOREBIRD_HOSTED_URL': 'http://139.199.88.243:9527/',
        'FLUTTER_STORAGE_BASE_URL': 'https://storage.flutter-io.cn',
        'META_OTA_API': 'http://139.199.88.243:9527/',
      });
      expect(env['SHOREBIRD_HOSTED_URL'], kShorebirdOfficialHostedUrl);
      expect(env['FLUTTER_STORAGE_BASE_URL'], kShorebirdFlutterStorageBaseUrl);
      expect(env['META_OTA_API'], 'http://139.199.88.243:9527/');
    });
  });

  group('PatchCompatGate.classifyPath', () {
    test('allows dart', () {
      expect(
        PatchCompatGate.classifyPath('metaapp_flutter/lib/main.dart'),
        isNull,
      );
    });

    test('blocks native and assets', () {
      expect(PatchCompatGate.classifyPath('android/app/build.gradle'), isNotNull);
      expect(PatchCompatGate.classifyPath('ios/Runner/Info.plist'), isNotNull);
      expect(
        PatchCompatGate.classifyPath('metaapp_flutter/assets/a.png'),
        isNotNull,
      );
    });

    test('blocks fvmrc', () {
      expect(PatchCompatGate.classifyPath('metaapp_flutter/.fvmrc'), isNotNull);
    });
  });
}
