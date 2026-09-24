import 'package:meta_tool/cache/cache_model.dart';
import 'package:meta_tool/commands/cache/use_cache_command.dart';
import 'package:meta_tool/define.dart';
import 'package:test/test.dart';

CacheModel _flutterModel({
  required String commitHash,
  required String releaseVersion,
  DateTime? commitTime,
}) {
  return CacheModel(
    buildPlatform: 'android',
    buildLibrary: BuildLibrary.flutter.name,
    buildType: BuildType.aar.name,
    branch: 'release',
    configuration: 'release',
    commitHash: commitHash,
    buildId: '0',
    commitTime: commitTime ?? DateTime.utc(2026, 9, 24),
    flutterSdk: '3.41.9@abc@shorebird',
    isShorebird: true,
    releaseVersion: releaseVersion,
  );
}

void main() {
  group('selectCacheByCommitOrReleaseVersion', () {
    final oldCommit = _flutterModel(
      commitHash: '34b215f8',
      releaseVersion: '3.5.0+1790212802',
      commitTime: DateTime.utc(2026, 9, 23),
    );
    final sameCommitNewer = _flutterModel(
      commitHash: '34b215f8',
      releaseVersion: '3.5.0+1790212802',
      commitTime: DateTime.utc(2026, 9, 24),
    );
    final otherVersion = _flutterModel(
      commitHash: 'aaaa1111',
      releaseVersion: '3.5.0+999',
      commitTime: DateTime.utc(2026, 9, 22),
    );

    test('prefers matching commitHash', () {
      final result = selectCacheByCommitOrReleaseVersion(
        candidates: [oldCommit, otherVersion],
        commitHash: '34b215f8',
        buildLibrary: BuildLibrary.flutter.name,
        releaseVersion: '3.5.0+1790212802',
      );
      expect(result.usedReleaseVersionFallback, isFalse);
      expect(result.models.map((e) => e.commitHash), ['34b215f8']);
    });

    test('falls back to same releaseVersion when commit misses', () {
      final result = selectCacheByCommitOrReleaseVersion(
        candidates: [oldCommit, otherVersion],
        commitHash: '691e6e57',
        buildLibrary: BuildLibrary.flutter.name,
        releaseVersion: '3.5.0+1790212802',
      );
      expect(result.usedReleaseVersionFallback, isTrue);
      expect(result.models.single.commitHash, '34b215f8');
      expect(result.models.single.releaseVersion, '3.5.0+1790212802');
    });

    test('returns empty when commit and releaseVersion both miss', () {
      final result = selectCacheByCommitOrReleaseVersion(
        candidates: [oldCommit, otherVersion],
        commitHash: '691e6e57',
        buildLibrary: BuildLibrary.flutter.name,
        releaseVersion: '3.5.0+1790212803',
      );
      expect(result.usedReleaseVersionFallback, isFalse);
      expect(result.models, isEmpty);
    });

    test('does not fall back without releaseVersion', () {
      final result = selectCacheByCommitOrReleaseVersion(
        candidates: [oldCommit],
        commitHash: '691e6e57',
        buildLibrary: BuildLibrary.flutter.name,
        releaseVersion: null,
      );
      expect(result.usedReleaseVersionFallback, isFalse);
      expect(result.models, isEmpty);
    });

    test('unity never falls back by releaseVersion', () {
      final unity = CacheModel(
        buildPlatform: 'android',
        buildLibrary: BuildLibrary.unity.name,
        buildType: BuildType.aar.name,
        branch: 'release2.0.0',
        configuration: 'release',
        commitHash: 'ccd7ba3f',
        buildId: '310026',
        commitTime: DateTime.utc(2026, 9, 24),
        releaseVersion: '3.5.0+1790212802',
      );
      final result = selectCacheByCommitOrReleaseVersion(
        candidates: [unity],
        commitHash: 'deadbeef',
        buildLibrary: BuildLibrary.unity.name,
        releaseVersion: '3.5.0+1790212802',
      );
      expect(result.usedReleaseVersionFallback, isFalse);
      expect(result.models, isEmpty);
    });

    test('null commitHash keeps all candidates', () {
      final result = selectCacheByCommitOrReleaseVersion(
        candidates: [oldCommit, sameCommitNewer, otherVersion],
        commitHash: null,
        buildLibrary: BuildLibrary.flutter.name,
        releaseVersion: '3.5.0+1790212802',
      );
      expect(result.usedReleaseVersionFallback, isFalse);
      expect(result.models, hasLength(3));
    });
  });
}
