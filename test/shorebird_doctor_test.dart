import 'dart:io';

import 'package:meta_tool/app_home_dir.dart';
import 'package:meta_tool/doctor.dart';
import 'package:meta_tool/shorebird_doctor.dart';
import 'package:path/path.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late AppHomeDir home;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('metax_shorebird_doctor_');
    Directory(join(tempDir.path, 'metaapp_flutter')).createSync();
    home = AppHomeDir(tempDir.path);
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  void writePubspec({bool? shorebirdEnabled}) {
    final buffer = StringBuffer('name: demo\n');
    if (shorebirdEnabled != null) {
      buffer.writeln('metax:');
      buffer.writeln('  shorebird_enabled: $shorebirdEnabled');
    }
    File(join(home.flutterDir.path, 'pubspec.yaml')).writeAsStringSync(
      buffer.toString(),
    );
  }

  void writeYaml({String? appId, String? baseUrl}) {
    final buffer = StringBuffer();
    if (appId != null) buffer.writeln('app_id: "$appId"');
    if (baseUrl != null) buffer.writeln('base_url: $baseUrl');
    File(join(home.flutterDir.path, 'shorebird.yaml')).writeAsStringSync(
      buffer.toString(),
    );
  }

  void writeFvmrc(String version) {
    File(join(home.flutterDir.path, '.fvmrc')).writeAsStringSync(version);
  }

  DoctorCheckItem item(DoctorReport report, String id) {
    return report.items.firstWhere((e) => e.id == id);
  }

  test('reports missing yaml / fvm / token as errors when offline', () async {
    writePubspec(shorebirdEnabled: false);
    final report = await ShorebirdDoctor(
      appHomeDir: home,
      environment: const {},
      checkNetwork: false,
      checkPatch: false,
    ).run();

    expect(item(report, 'shorebird_yaml').ok, isFalse);
    expect(item(report, 'flutter_version').ok, isFalse);
    expect(item(report, 'shorebird_enabled').ok, isFalse);
    expect(
      item(report, 'shorebird_enabled').severity,
      DoctorCheckSeverity.warning,
    );
    expect(item(report, 'shorebird_auth').ok, isFalse);
    expect(item(report, 'shorebird_auth').detail, contains('FLUTTERPATCH_TOKEN'));
  });

  test('passes project checks when configured', () async {
    writePubspec(shorebirdEnabled: true);
    writeYaml(appId: 'app-123', baseUrl: 'http://ota.local/');
    writeFvmrc('3.27.4');

    final report = await ShorebirdDoctor(
      appHomeDir: home,
      environment: const {
        'FLUTTERPATCH_TOKEN': 'fp_test_token',
      },
      checkNetwork: false,
      checkPatch: false,
    ).run();

    expect(item(report, 'shorebird_yaml').ok, isTrue);
    expect(item(report, 'flutter_version').ok, isTrue);
    expect(item(report, 'flutter_version').detail, contains('3.27.4'));
    expect(item(report, 'shorebird_enabled').ok, isTrue);
    expect(item(report, 'shorebird_auth').ok, isTrue);
    expect(item(report, 'shorebird_auth').detail, contains('FLUTTERPATCH_TOKEN'));
  });

  test('resolves flutter version from melos root .fvmrc', () async {
    writePubspec(shorebirdEnabled: true);
    writeYaml(appId: 'app-123');
    File(join(tempDir.path, '.fvmrc')).writeAsStringSync('3.29.0');

    final report = await ShorebirdDoctor(
      appHomeDir: home,
      environment: const {
        'FLUTTERPATCH_TOKEN': 'fp_test_token',
      },
      checkNetwork: false,
    ).run();

    expect(item(report, 'flutter_version').ok, isTrue);
    expect(item(report, 'flutter_version').detail, contains('3.29.0'));
  });

  test('warns when only legacy SHOREBIRD_TOKEN is set', () async {
    writePubspec(shorebirdEnabled: true);
    writeYaml(appId: 'app-123');
    writeFvmrc('3.27.4');

    final report = await ShorebirdDoctor(
      appHomeDir: home,
      environment: const {'SHOREBIRD_TOKEN': 'sb_api_x'},
      checkNetwork: false,
    ).run();

    final auth = item(report, 'shorebird_auth');
    expect(auth.ok, isFalse);
    expect(auth.severity, DoctorCheckSeverity.warning);
    expect(auth.detail, contains('FLUTTERPATCH_TOKEN'));
  });

  test('warns when SHOREBIRD_HOSTED_URL is set', () async {
    writePubspec(shorebirdEnabled: true);
    writeYaml(appId: 'app-123');
    writeFvmrc('3.27.4');

    final report = await ShorebirdDoctor(
      appHomeDir: home,
      environment: const {
        'FLUTTERPATCH_TOKEN': 'fp_test_token',
        'SHOREBIRD_HOSTED_URL': 'http://119.23.47.1:9527/',
      },
      checkNetwork: false,
    ).run();

    final env = item(report, 'env_override');
    expect(env.ok, isFalse);
    expect(env.severity, DoctorCheckSeverity.warning);
    expect(env.detail, contains('SHOREBIRD_HOSTED_URL'));
  });

  test('--patch checks meta_ota credentials', () async {
    writePubspec(shorebirdEnabled: true);
    writeYaml(appId: 'app-123', baseUrl: 'http://ota.local/');
    writeFvmrc('3.27.4');

    final missing = await ShorebirdDoctor(
      appHomeDir: home,
      environment: {
        'HOME': tempDir.path,
        'FLUTTERPATCH_TOKEN': 'fp_test_token',
      },
      checkNetwork: false,
      checkPatch: true,
    ).run();
    expect(item(missing, 'meta_ota_creds').ok, isFalse);

    final ok = await ShorebirdDoctor(
      appHomeDir: home,
      environment: {
        'HOME': tempDir.path,
        'FLUTTERPATCH_TOKEN': 'fp_test_token',
        'META_OTA_API': 'http://ota.local/',
        'META_OTA_TOKEN': 'secret',
        'META_OTA_BIN': '/usr/bin/true',
      },
      checkNetwork: false,
      checkPatch: true,
    ).run();
    expect(item(ok, 'meta_ota_creds').ok, isTrue);
    expect(item(ok, 'meta_ota_bin').ok, isTrue);
  });
}
