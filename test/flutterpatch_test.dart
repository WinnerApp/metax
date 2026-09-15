import 'dart:io';

import 'package:meta_tool/app_home_dir.dart';
import 'package:meta_tool/cache/cache_model.dart';
import 'package:meta_tool/flutterpatch.dart';
import 'package:path/path.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late AppHomeDir home;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('metax_flutterpatch_');
    Directory(join(tempDir.path, 'metaapp_flutter')).createSync();
    home = AppHomeDir(tempDir.path);
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  void writePubspec({required bool? flutterPatchEnabled}) {
    final buffer = StringBuffer('name: demo\n');
    if (flutterPatchEnabled != null) {
      buffer.writeln('metax:');
      buffer.writeln('  shorebird_enabled: $flutterPatchEnabled');
    }
    File(join(home.flutterDir.path, 'pubspec.yaml')).writeAsStringSync(
      buffer.toString(),
    );
  }

  group('resolveUseFlutterPatch', () {
    test('defaults off without pubspec field', () {
      writePubspec(flutterPatchEnabled: null);
      File(join(home.flutterDir.path, 'shorebird.yaml')).writeAsStringSync('''
app_id: "abc"
base_url: http://ota.local
''');
      final r = resolveUseFlutterPatch(appHomeDir: home, environment: {});
      expect(r.enabled, isFalse);
      expect(r.reason, contains('unset'));
    });

    test('pubspec metax.shorebird_enabled true enables', () {
      writePubspec(flutterPatchEnabled: true);
      File(join(home.flutterDir.path, 'shorebird.yaml')).writeAsStringSync('''
app_id: "abc"
''');
      final r = resolveUseFlutterPatch(appHomeDir: home, environment: {});
      expect(r.enabled, isTrue);
      expect(r.yaml?.appId, 'abc');
      expect(r.reason, contains('pubspec.yaml'));
    });

    test('file existence alone does not enable', () {
      writePubspec(flutterPatchEnabled: false);
      File(join(home.flutterDir.path, 'shorebird.yaml')).writeAsStringSync('''
app_id: "abc"
''');
      final r = resolveUseFlutterPatch(appHomeDir: home, environment: {});
      expect(r.enabled, isFalse);
    });

    test('CLI overrides pubspec', () {
      writePubspec(flutterPatchEnabled: true);
      final off = resolveUseFlutterPatch(
        appHomeDir: home,
        explicitUseFlutterPatch: false,
        environment: {},
      );
      expect(off.enabled, isFalse);

      writePubspec(flutterPatchEnabled: false);
      final on = resolveUseFlutterPatch(
        appHomeDir: home,
        explicitUseFlutterPatch: true,
        environment: {},
      );
      expect(on.enabled, isTrue);
    });

    test('env overrides pubspec', () {
      writePubspec(flutterPatchEnabled: true);
      final r = resolveUseFlutterPatch(
        appHomeDir: home,
        environment: {'FLUTTERPATCH_ENABLED': 'false'},
      );
      expect(r.enabled, isFalse);
    });

    test('legacy SHOREBIRD_ENABLED still works', () {
      writePubspec(flutterPatchEnabled: false);
      final r = resolveUseFlutterPatch(
        appHomeDir: home,
        environment: {'SHOREBIRD_ENABLED': 'true'},
      );
      expect(r.enabled, isTrue);
      expect(r.reason, contains('SHOREBIRD_ENABLED'));
    });

    test('legacy pubspec shorebird_enabled still works', () {
      File(join(home.flutterDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: demo
metax:
  shorebird_enabled: true
''');
      final r = resolveUseFlutterPatch(appHomeDir: home, environment: {});
      expect(r.enabled, isTrue);
    });

    test('top-level metax_enabled in pubspec', () {
      File(join(home.flutterDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: demo
metax_enabled: true
''');
      final r = resolveUseFlutterPatch(appHomeDir: home, environment: {});
      expect(r.enabled, isTrue);
    });
  });

  group('buildFlutterPatchReleaseVersion', () {
    test('joins name and number', () {
      expect(
        buildFlutterPatchReleaseVersion(buildName: '1.2.3', buildNumber: '9'),
        '1.2.3+9',
      );
    });
  });

  group('parseFlutterPatchReleaseVersion', () {
    test('round-trips with buildFlutterPatchReleaseVersion', () {
      final v = buildFlutterPatchReleaseVersion(
        buildName: '1.2.3',
        buildNumber: '9',
      );
      final parsed = parseFlutterPatchReleaseVersion(v);
      expect(parsed.buildName, '1.2.3');
      expect(parsed.buildNumber, '9');
    });
  });

  group('flutterPatchCliEnvironment', () {
    test('removes SHOREBIRD_HOSTED_URL and forces storage base', () {
      final env = flutterPatchCliEnvironment({
        'SHOREBIRD_HOSTED_URL': 'http://139.199.88.243:9527/',
        'FLUTTER_STORAGE_BASE_URL': 'https://storage.flutter-io.cn',
        'CUSTOM_PASS_THROUGH': 'http://139.199.88.243:9527/',
        'FLUTTERPATCH_TOKEN': 'tok',
      });
      expect(env.containsKey('SHOREBIRD_HOSTED_URL'), isFalse);
      expect(env['FLUTTER_STORAGE_BASE_URL'], kFlutterPatchStorageBaseUrl);
      expect(env['CUSTOM_PASS_THROUGH'], 'http://139.199.88.243:9527/');
      expect(env['FLUTTERPATCH_TOKEN'], 'tok');
    });
  });

  group('resolveFlutterPatchCli', () {
    test('defaults to flutterpatch', () {
      expect(resolveFlutterPatchCli({}), kFlutterPatchCliName);
    });

    test('prefers FLUTTERPATCH_BIN', () {
      expect(
        resolveFlutterPatchCli({'FLUTTERPATCH_BIN': '/opt/fp/bin/flutterpatch'}),
        '/opt/fp/bin/flutterpatch',
      );
    });
  });

  group('buildFlutterPatchCheckOtaArgs', () {
    test('passes --flutter after code update so CLI can authorize the tree', () {
      expect(
        buildFlutterPatchCheckOtaArgs(
          flutterDir: '/app/metaapp_flutter',
          platform: 'android',
          releaseVersion: '3.4.100+1',
          androidDir: '/app/android',
          unsupportedOut: '/tmp/u.json',
          supportedOut: '/tmp/s.json',
        ),
        [
          '--json',
          'check-ota',
          '--flutter',
          '/app/metaapp_flutter',
          '--platform',
          'android',
          '--version',
          '3.4.100+1',
          '--no-write',
          '--unsupported-out',
          '/tmp/u.json',
          '--supported-out',
          '/tmp/s.json',
          '--android',
          '/app/android',
        ],
      );
    });
  });

  group('parseLastJsonObject', () {
    test('reads last JSON object from mixed output', () {
      final json = parseLastJsonObject(
        'log\n{"ota_supported":false}\n{"ota_supported":true,"n":1}\n',
      );
      expect(json?['ota_supported'], isTrue);
      expect(json?['n'], 1);
    });
  });

  group('maybeCloneFlutterPatchReleaseFromCache', () {
    test('skips when cached releaseVersion empty', () async {
      final cloned = await maybeCloneFlutterPatchReleaseFromCache(
        flutterDir: home.flutterDir,
        platform: 'aar',
        releaseVersion: '1.0.0+2',
        cachedReleaseVersion: '',
      );
      expect(cloned, isFalse);
    });

    test('skips when versions equal', () async {
      final cloned = await maybeCloneFlutterPatchReleaseFromCache(
        flutterDir: home.flutterDir,
        platform: 'aar',
        releaseVersion: '1.0.0+1',
        cachedReleaseVersion: '1.0.0+1',
      );
      expect(cloned, isFalse);
    });
  });

  group('CacheModel releaseVersion', () {
    test('round-trips json and is ignored by equality', () {
      final a = CacheModel(
        buildPlatform: 'ios',
        buildLibrary: 'flutter',
        buildType: 'framework',
        branch: 'main',
        configuration: 'release',
        commitHash: 'abc',
        buildId: '0',
        commitTime: DateTime.utc(2026, 1, 1),
        isShorebird: true,
        releaseVersion: '1.0.0+1',
      );
      final b = a.copyWith(releaseVersion: '1.0.0+2');
      expect(a == b, isTrue);
      expect(a.toJson()['releaseVersion'], '1.0.0+1');
      expect(CacheModel.fromJson(a.toJson()).releaseVersion, '1.0.0+1');
    });
  });

  group('clearFlutterPatchReleaseDir', () {
    test('deletes existing flutter/release', () async {
      final release = Directory(join(home.flutterDir.path, 'release'))
        ..createSync();
      File(join(release.path, 'App.xcframework')).writeAsStringSync('ios');
      await clearFlutterPatchReleaseDir(home.flutterDir);
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

  group('syncFlutterPatchAarReleaseToHostDir', () {
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

      await syncFlutterPatchAarReleaseToHostDir(home.flutterDir);

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

      await syncFlutterPatchAarReleaseToHostDir(home.flutterDir);

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

      await syncFlutterPatchAarReleaseToHostDir(home.flutterDir);

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
