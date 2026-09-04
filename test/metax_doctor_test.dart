import 'dart:io';

import 'package:meta_tool/app_home_dir.dart';
import 'package:meta_tool/doctor.dart';
import 'package:meta_tool/metax_doctor.dart';
import 'package:path/path.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late AppHomeDir home;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('metax_doctor_');
    Directory(join(tempDir.path, 'metaapp_flutter')).createSync();
    Directory(join(tempDir.path, 'ios')).createSync();
    Directory(join(tempDir.path, 'android')).createSync();
    Directory(join(tempDir.path, 'jenkins_ci', 'env', 'app'))
        .createSync(recursive: true);
    Directory(join(tempDir.path, 'jenkins_ci', 'env', 'appwrite'))
        .createSync(recursive: true);
    home = AppHomeDir(tempDir.path);
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  DoctorCheckItem item(DoctorReport report, String id) {
    return report.items.firstWhere((e) => e.id == id);
  }

  test('reports missing core project files', () async {
    final report = await MetaxDoctor(
      appHomeDir: home,
      environment: {'PATH': '/usr/bin:/bin:/usr/local/bin'},
      options: const MetaxDoctorOptions(
        platforms: {'android'},
        checkShorebird: false,
        checkNetwork: false,
      ),
    ).run();

    expect(item(report, 'dir_flutter').ok, isTrue);
    expect(item(report, 'env_app').ok, isFalse);
    expect(item(report, 'flutter_pubspec').ok, isFalse);
    expect(item(report, 'flutter_fvmrc').ok, isFalse);
    expect(item(report, 'android_gradlew').ok, isFalse);
  });

  test('reads sdk.dir / ndk.dir from local.properties', () async {
    File(join(home.flutterDir.path, 'pubspec.yaml')).writeAsStringSync(
      'name: demo\n',
    );
    File(join(home.flutterDir.path, '.fvmrc')).writeAsStringSync('3.27.4');
    File(join(tempDir.path, 'jenkins_ci', 'env', 'app', '.env'))
        .writeAsStringSync('FOO=1\n');
    File(join(tempDir.path, 'jenkins_ci', 'env', 'appwrite', '.env'))
        .writeAsStringSync('APPWRITE_ENDPOINT=http://x\n');

    final sdk = Directory(join(tempDir.path, 'fake_sdk'))..createSync();
    final ndk = Directory(join(tempDir.path, 'fake_ndk'))..createSync();
    File(join(ndk.path, 'ndk-build')).writeAsStringSync('#!/bin/sh\n');
    File(join(home.androidDir.path, 'gradlew')).writeAsStringSync('#!/bin/sh\n');
    File(join(home.androidDir.path, 'local.properties')).writeAsStringSync('''
sdk.dir=${sdk.path}
ndk.dir=${ndk.path}
''');

    final report = await MetaxDoctor(
      appHomeDir: home,
      environment: {
        'PATH': Platform.environment['PATH'] ?? '/usr/bin:/bin',
        'HOME': tempDir.path,
      },
      options: const MetaxDoctorOptions(
        platforms: {'android'},
        checkShorebird: false,
        checkNetwork: false,
      ),
    ).run();

    expect(item(report, 'android_gradlew').ok, isTrue);
    expect(item(report, 'android_sdk_dir').ok, isTrue);
    expect(item(report, 'android_ndk_dir').ok, isTrue);
    expect(item(report, 'env_app').ok, isTrue);
  });

  test('reads FVM version from melos workspace root', () async {
    File(join(tempDir.path, '.fvmrc')).writeAsStringSync('3.27.4');
    // metaapp_flutter 本身无 .fvmrc
    File(join(home.flutterDir.path, 'pubspec.yaml')).writeAsStringSync(
      'name: demo\n',
    );
    File(join(tempDir.path, 'jenkins_ci', 'env', 'app', '.env'))
        .writeAsStringSync('FOO=1\n');
    File(join(tempDir.path, 'jenkins_ci', 'env', 'appwrite', '.env'))
        .writeAsStringSync('X=1\n');
    File(join(home.androidDir.path, 'gradlew')).writeAsStringSync('#!/bin/sh\n');
    final sdk = Directory(join(tempDir.path, 'fake_sdk'))..createSync();
    final ndk = Directory(join(tempDir.path, 'fake_ndk'))..createSync();
    File(join(ndk.path, 'ndk-build')).writeAsStringSync('#!/bin/sh\n');
    File(join(home.androidDir.path, 'local.properties')).writeAsStringSync('''
sdk.dir=${sdk.path}
ndk.dir=${ndk.path}
''');

    final report = await MetaxDoctor(
      appHomeDir: home,
      environment: {
        'PATH': Platform.environment['PATH'] ?? '/usr/bin:/bin',
        'HOME': tempDir.path,
      },
      options: const MetaxDoctorOptions(
        platforms: {'android'},
        checkShorebird: true,
        checkNetwork: false,
      ),
    ).run();

    expect(item(report, 'flutter_fvmrc').ok, isTrue);
    expect(item(report, 'flutter_fvmrc').detail, contains('3.27.4'));
    expect(item(report, 'flutter_version').ok, isTrue);
  });

  test('reports missing NDK directory clearly', () async {
    File(join(home.flutterDir.path, 'pubspec.yaml')).writeAsStringSync(
      'name: demo\n',
    );
    File(join(tempDir.path, '.fvmrc')).writeAsStringSync('3.27.4');
    File(join(tempDir.path, 'jenkins_ci', 'env', 'app', '.env'))
        .writeAsStringSync('FOO=1\n');
    File(join(tempDir.path, 'jenkins_ci', 'env', 'appwrite', '.env'))
        .writeAsStringSync('X=1\n');
    File(join(home.androidDir.path, 'gradlew')).writeAsStringSync('#!/bin/sh\n');
    final sdk = Directory(join(tempDir.path, 'fake_sdk'))..createSync();
    File(join(home.androidDir.path, 'local.properties')).writeAsStringSync('''
sdk.dir=${sdk.path}
ndk.dir=${join(tempDir.path, 'missing_ndk_27')}
''');

    final report = await MetaxDoctor(
      appHomeDir: home,
      environment: {
        'PATH': '/usr/bin:/bin',
        'HOME': tempDir.path,
      },
      options: const MetaxDoctorOptions(
        platforms: {'android'},
        checkShorebird: false,
        checkNetwork: false,
      ),
    ).run();

    expect(item(report, 'android_ndk_dir').ok, isFalse);
    expect(item(report, 'android_ndk_dir').detail, contains('不存在'));
  });

  test('unity flag checks build_winner_app', () async {
    File(join(home.flutterDir.path, 'pubspec.yaml')).writeAsStringSync(
      'name: demo\n',
    );
    File(join(tempDir.path, '.fvmrc')).writeAsStringSync('3.27.4');
    File(join(tempDir.path, 'jenkins_ci', 'env', 'app', '.env'))
        .writeAsStringSync('UNITY_WORKSPACE=/tmp\n');
    File(join(tempDir.path, 'jenkins_ci', 'env', 'appwrite', '.env'))
        .writeAsStringSync('X=1\n');

    final report = await MetaxDoctor(
      appHomeDir: home,
      environment: {
        'PATH': '/usr/bin:/bin',
        'HOME': tempDir.path,
      },
      options: const MetaxDoctorOptions(
        platforms: {'ios'},
        checkUnity: true,
        checkShorebird: false,
        checkNetwork: false,
      ),
    ).run();

    expect(
      report.items.any((e) => e.id == 'cmd_build_winner_app'),
      isTrue,
    );
    expect(item(report, 'cmd_build_winner_app').ok, isFalse);
  });
}
