import 'dart:io';

import 'package:meta_tool/app_home_dir.dart';
import 'package:meta_tool/cache/cache_model.dart';
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
    test('removes SHOREBIRD_HOSTED_URL and forces storage base', () {
      final env = shorebirdCliEnvironment({
        'SHOREBIRD_HOSTED_URL': 'http://139.199.88.243:9527/',
        'FLUTTER_STORAGE_BASE_URL': 'https://storage.flutter-io.cn',
        'CUSTOM_PASS_THROUGH': 'http://139.199.88.243:9527/',
        'FLUTTERPATCH_TOKEN': 'tok',
      });
      expect(env.containsKey('SHOREBIRD_HOSTED_URL'), isFalse);
      expect(env['FLUTTER_STORAGE_BASE_URL'], kShorebirdFlutterStorageBaseUrl);
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
