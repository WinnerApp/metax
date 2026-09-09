import 'dart:io';

import 'package:meta_tool/app_home_dir.dart';
import 'package:meta_tool/meta_ota.dart';
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

  group('parseShorebirdReleaseVersion', () {
    test('round-trips with buildShorebirdReleaseVersion', () {
      final v = buildShorebirdReleaseVersion(
        buildName: '1.2.3',
        buildNumber: '9',
      );
      final parsed = parseShorebirdReleaseVersion(v);
      expect(parsed.buildName, '1.2.3');
      expect(parsed.buildNumber, '9');
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

  group('resolveMetaOtaBin', () {
    test('prefers META_OTA_BIN file path', () async {
      final bin = File(join(tempDir.path, 'fake_meta_ota'))..writeAsStringSync('#!/bin/sh\n');
      final path = await resolveMetaOtaBin(environment: {
        'META_OTA_BIN': bin.path,
      });
      expect(path, bin.absolute.path);
    });

    test('prefers META_CODE_PUSH_ROOT dist/meta_ota', () async {
      final root = Directory(join(tempDir.path, 'meta_code_push'))..createSync();
      final dist = Directory(join(root.path, 'dist'))..createSync();
      final bin = File(join(dist.path, 'meta_ota'))..writeAsStringSync('x');
      final path = await resolveMetaOtaBin(environment: {
        'META_OTA_BIN': '',
        'META_CODE_PUSH_ROOT': root.path,
      });
      expect(path, bin.absolute.path);
    });
  });

  group('tryResolveMetaOtaCredentials', () {
    test('resolves from env and strips trailing slash', () {
      File(join(home.flutterDir.path, 'shorebird.yaml')).writeAsStringSync('''
app_id: "app-from-yaml"
base_url: http://ota.yaml/
''');
      final creds = tryResolveMetaOtaCredentials(
        flutterDir: home.flutterDir,
        environment: {
          'META_OTA_API': 'http://ota.env/',
          'META_OTA_TOKEN': 'tok',
          'HOME': tempDir.path,
        },
      );
      expect(creds, isNotNull);
      expect(creds!.api, 'http://ota.env');
      expect(creds.token, 'tok');
      expect(creds.appId, 'app-from-yaml');
    });

    test('requireAppId returns null without app_id', () {
      final creds = tryResolveMetaOtaCredentials(
        flutterDir: home.flutterDir,
        environment: {
          'META_OTA_API': 'http://ota.env/',
          'META_OTA_TOKEN': 'tok',
          'HOME': tempDir.path,
        },
        requireAppId: true,
      );
      expect(creds, isNull);
    });
  });

  group('syncShorebirdReleaseToMetaOta', () {
    test('skips when META_OTA_SKIP_RELEASE_SYNC is set', () async {
      await syncShorebirdReleaseToMetaOta(
        appHomeDir: home,
        platform: 'android',
        releaseVersion: '1.0.0+1',
        environment: {
          'META_OTA_SKIP_RELEASE_SYNC': 'true',
          'META_OTA_API': 'http://ota.env/',
          'META_OTA_TOKEN': 'tok',
          'META_OTA_APP_ID': 'app-1',
          'HOME': tempDir.path,
        },
      );
    });

    test('skips when meta_ota bin missing', () async {
      await syncShorebirdReleaseToMetaOta(
        appHomeDir: home,
        platform: 'android',
        releaseVersion: '1.0.0+1',
        environment: {
          'HOME': tempDir.path,
          'META_OTA_BIN': join(tempDir.path, 'no_such_meta_ota'),
          'META_CODE_PUSH_ROOT': '',
          'PATH': '',
        },
      );
    });
  });

  File writeFakeMetaOtaRecorder() {
    final logFile = File(join(tempDir.path, 'meta_ota_calls.log'));
    final bin = File(join(tempDir.path, 'fake_meta_ota'));
    // Records argv; fails if --api/--token appear.
    bin.writeAsStringSync('''
#!/bin/sh
echo "\$@" >> "${logFile.path}"
for arg in "\$@"; do
  if [ "\$arg" = "--api" ] || [ "\$arg" = "--token" ]; then
    echo "forbidden flag: \$arg" >&2
    exit 2
  fi
done
exit 0
''');
    Process.runSync('chmod', ['+x', bin.path]);
    return bin;
  }

  group('syncShorebirdBaselineToMetaOta', () {
    test('skips when META_OTA_SKIP_BASELINE_SYNC is set', () async {
      final bin = writeFakeMetaOtaRecorder();
      final logFile = File(join(tempDir.path, 'meta_ota_calls.log'));
      await syncShorebirdBaselineToMetaOta(
        appHomeDir: home,
        releaseVersion: '1.0.0+1',
        environment: {
          'META_OTA_SKIP_BASELINE_SYNC': 'true',
          'META_OTA_BIN': bin.path,
          'HOME': tempDir.path,
        },
      );
      expect(logFile.existsSync(), isFalse);
    });

    test('skips when meta_ota bin missing', () async {
      await syncShorebirdBaselineToMetaOta(
        appHomeDir: home,
        releaseVersion: '1.0.0+1',
        environment: {
          'HOME': tempDir.path,
          'META_OTA_BIN': join(tempDir.path, 'no_such_meta_ota'),
          'META_CODE_PUSH_ROOT': '',
          'PATH': '',
        },
      );
    });

    test('runs upload-snapshot and upload-resources without --api/--token',
        () async {
      final bin = writeFakeMetaOtaRecorder();
      final logFile = File(join(tempDir.path, 'meta_ota_calls.log'));
      Directory(join(tempDir.path, 'android')).createSync();
      Directory(join(tempDir.path, 'ios')).createSync();

      await syncShorebirdBaselineToMetaOta(
        appHomeDir: home,
        releaseVersion: '1.0.0+42',
        environment: {
          'META_OTA_BIN': bin.path,
          'HOME': tempDir.path,
          'PATH': '',
        },
      );

      final log = logFile.readAsStringSync();
      expect(log, contains('upload-snapshot'));
      expect(log, contains('upload-resources'));
      expect(log, contains('1.0.0+42'));
      expect(log, contains('--flutter metaapp_flutter'));
      expect(log, contains('--android android'));
      expect(log, contains('--ios ios'));
      expect(log, contains('--app-dir metaapp_flutter'));
      expect(log, isNot(contains('--api')));
      expect(log, isNot(contains('--token')));
    });
  });

  group('uploadMetaOtaResourcePack', () {
    test('skips when META_OTA_SKIP_RESOURCE_PACK is set', () async {
      final bin = writeFakeMetaOtaRecorder();
      final logFile = File(join(tempDir.path, 'meta_ota_calls.log'));
      await uploadMetaOtaResourcePack(
        appHomeDir: home,
        releaseVersion: '1.0.0+2',
        environment: {
          'META_OTA_SKIP_RESOURCE_PACK': 'true',
          'META_OTA_BIN': bin.path,
          'HOME': tempDir.path,
        },
      );
      expect(logFile.existsSync(), isFalse);
    });

    test('skips when skip flag is true', () async {
      final bin = writeFakeMetaOtaRecorder();
      final logFile = File(join(tempDir.path, 'meta_ota_calls.log'));
      await uploadMetaOtaResourcePack(
        appHomeDir: home,
        releaseVersion: '1.0.0+2',
        skip: true,
        environment: {
          'META_OTA_BIN': bin.path,
          'HOME': tempDir.path,
        },
      );
      expect(logFile.existsSync(), isFalse);
    });

    test('runs upload-resource-pack without --api/--token', () async {
      final bin = writeFakeMetaOtaRecorder();
      final logFile = File(join(tempDir.path, 'meta_ota_calls.log'));
      await uploadMetaOtaResourcePack(
        appHomeDir: home,
        releaseVersion: '1.0.0+2',
        environment: {
          'META_OTA_BIN': bin.path,
          'HOME': tempDir.path,
          'PATH': '',
        },
      );
      final log = logFile.readAsStringSync();
      expect(log, contains('upload-resource-pack'));
      expect(log, contains('--app-dir .'));
      expect(log, contains('1.0.0+2'));
      expect(log, isNot(contains('--api')));
      expect(log, isNot(contains('--token')));
    });
  });

  group('clearShorebirdReleaseDir', () {
    test('deletes existing flutter/release', () async {
      final release = Directory(join(home.flutterDir.path, 'release'))
        ..createSync();
      File(join(release.path, 'App.xcframework')).writeAsStringSync('ios');
      await clearShorebirdReleaseDir(home.flutterDir);
      expect(release.existsSync(), isFalse);
    });
  });

  group('stripIosArtifactsFromCacheDir', () {
    test('removes xcframework and podspec but keeps android maven layout',
        () async {
      final host = Directory(join(tempDir.path, 'host'))..createSync();
      Directory(join(host.path, 'App.xcframework')).createSync();
      Directory(join(host.path, 'ShorebirdFlutter.xcframework')).createSync();
      File(join(host.path, 'Flutter.podspec')).writeAsStringSync('pod');
      Directory(join(host.path, 'com', 'example')).createSync(recursive: true);
      File(join(host.path, 'com', 'example', 'lib.aar')).writeAsStringSync('a');

      final removed = await stripIosArtifactsFromCacheDir(host);
      expect(removed, 3);
      expect(Directory(join(host.path, 'App.xcframework')).existsSync(), isFalse);
      expect(
        Directory(join(host.path, 'ShorebirdFlutter.xcframework')).existsSync(),
        isFalse,
      );
      expect(File(join(host.path, 'Flutter.podspec')).existsSync(), isFalse);
      expect(
        File(join(host.path, 'com', 'example', 'lib.aar')).existsSync(),
        isTrue,
      );
    });
  });

  group('stripAndroidArtifactsFromCacheDir', () {
    test('removes android_generated and aar but keeps xcframework', () async {
      final framework = Directory(join(tempDir.path, 'framework'))..createSync();
      Directory(join(framework.path, 'App.xcframework')).createSync();
      Directory(join(framework.path, 'android_generated')).createSync();
      File(join(framework.path, 'plugin.aar')).writeAsStringSync('a');

      final removed = await stripAndroidArtifactsFromCacheDir(framework);
      expect(removed, 2);
      expect(
        Directory(join(framework.path, 'App.xcframework')).existsSync(),
        isTrue,
      );
      expect(
        Directory(join(framework.path, 'android_generated')).existsSync(),
        isFalse,
      );
      expect(File(join(framework.path, 'plugin.aar')).existsSync(), isFalse);
    });
  });

  group('resolveMetaOtaPatchedBinary', () {
    test('prefers AAR host jni libapp.so over missing full-app path', () {
      final so = File(
        join(
          home.flutterDir.path,
          'build',
          'host',
          'outputs',
          'repo',
          'com',
          'winner',
          'meta_flutter',
          'flutter_release',
          '1.0',
          'flutter_release-1.0',
          'jni',
          'arm64-v8a',
          'libapp.so',
        ),
      );
      so.createSync(recursive: true);
      so.writeAsStringSync('patched');

      final path = resolveMetaOtaPatchedBinary(
        flutterDir: home.flutterDir,
        platform: 'android',
        arch: 'aarch64',
        environment: {},
      );
      expect(path, so.absolute.path);
    });

    test('uses full-app stripped_native_libs when present', () {
      final so = File(
        join(
          home.flutterDir.path,
          'build',
          'app',
          'intermediates',
          'stripped_native_libs',
          'release',
          'stripReleaseDebugSymbols',
          'out',
          'lib',
          'arm64-v8a',
          'libapp.so',
        ),
      );
      so.createSync(recursive: true);
      so.writeAsStringSync('full-app');

      final path = resolveMetaOtaPatchedBinary(
        flutterDir: home.flutterDir,
        platform: 'android',
        arch: 'aarch64',
        environment: {},
      );
      expect(path, so.absolute.path);
    });

    test('META_OTA_PATCH_LIBAPP wins', () {
      final explicit = File(join(tempDir.path, 'custom_libapp.so'))
        ..writeAsStringSync('x');
      final path = resolveMetaOtaPatchedBinary(
        flutterDir: home.flutterDir,
        platform: 'android',
        environment: {'META_OTA_PATCH_LIBAPP': explicit.path},
      );
      expect(path, explicit.absolute.path);
    });

    test('resolves ios out.vmcode', () {
      final vm = File(join(home.flutterDir.path, 'build', 'out.vmcode'))
        ..createSync(recursive: true);
      vm.writeAsStringSync('vm');
      final path = resolveMetaOtaPatchedBinary(
        flutterDir: home.flutterDir,
        platform: 'ios',
        environment: {},
      );
      expect(path, vm.absolute.path);
    });
  });

  group('syncShorebirdAarReleaseToHostDir', () {
    test('copies flat release maven into build/host/outputs/repo', () async {
      final release = Directory(join(home.flutterDir.path, 'release'))
        ..createSync();
      Directory(join(release.path, 'com', 'winner', 'meta_flutter'))
          .createSync(recursive: true);
      File(
        join(
          release.path,
          'com',
          'winner',
          'meta_flutter',
          'flutter_release-1.0.aar',
        ),
      ).writeAsStringSync('aar');
      Directory(join(release.path, 'android_generated')).createSync();

      await syncShorebirdAarReleaseToHostDir(home.flutterDir);

      final aar = File(
        join(
          home.flutterDir.path,
          'build',
          'host',
          'outputs',
          'repo',
          'com',
          'winner',
          'meta_flutter',
          'flutter_release-1.0.aar',
        ),
      );
      expect(aar.existsSync(), isTrue);
      expect(
        Directory(join(home.flutterDir.path, 'build', 'host', 'com'))
            .existsSync(),
        isFalse,
      );
    });

    test('unwraps release that already contains outputs/repo', () async {
      final releaseRepo = Directory(
        join(home.flutterDir.path, 'release', 'outputs', 'repo'),
      )..createSync(recursive: true);
      Directory(join(releaseRepo.path, 'com', 'example'))
          .createSync(recursive: true);
      File(join(releaseRepo.path, 'com', 'example', 'lib.aar'))
          .writeAsStringSync('a');

      await syncShorebirdAarReleaseToHostDir(home.flutterDir);

      expect(
        File(
          join(
            home.flutterDir.path,
            'build',
            'host',
            'outputs',
            'repo',
            'com',
            'example',
            'lib.aar',
          ),
        ).existsSync(),
        isTrue,
      );
      expect(
        Directory(
          join(
            home.flutterDir.path,
            'build',
            'host',
            'outputs',
            'repo',
            'outputs',
          ),
        ).existsSync(),
        isFalse,
      );
    });

    test('normalizes flat build/host when release is missing', () async {
      final host = Directory(join(home.flutterDir.path, 'build', 'host'))
        ..createSync(recursive: true);
      File(join(host.path, 'cache.json')).writeAsStringSync('{}');
      Directory(join(host.path, 'com', 'winner')).createSync(recursive: true);
      File(join(host.path, 'com', 'winner', 'x.aar')).writeAsStringSync('a');

      await syncShorebirdAarReleaseToHostDir(home.flutterDir);

      expect(File(join(host.path, 'cache.json')).existsSync(), isTrue);
      expect(
        File(join(host.path, 'outputs', 'repo', 'com', 'winner', 'x.aar'))
            .existsSync(),
        isTrue,
      );
      expect(Directory(join(host.path, 'com')).existsSync(), isFalse);
    });
  });
}
