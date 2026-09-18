import 'dart:io';

import 'package:meta_tool/cache/cache.dart';
import 'package:meta_tool/cache/cache_manager.dart';
import 'package:meta_tool/cache/cache_model.dart';
import 'package:path/path.dart';
import 'package:test/test.dart';

class _FileCacheManager extends CacheManager {
  _FileCacheManager(super.cacheFilePath);
}

class _TestCache extends Cache {
  _TestCache(String home, CacheManager manager) : super(home, manager);
}

void main() {
  late Directory tempDir;
  late _FileCacheManager manager;
  late _TestCache cache;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('metax_cache_slot_');
    manager = _FileCacheManager(join(tempDir.path, 'cache.json'));
    cache = _TestCache(tempDir.path, manager);
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  CacheModel model({
    required CacheArtifactKind kind,
    String commit = 'abc123',
  }) {
    return CacheModel(
      buildPlatform: 'android',
      buildLibrary: 'flutter',
      buildType: 'aar',
      branch: 'main',
      configuration: 'release',
      commitHash: commit,
      buildId: '0',
      commitTime: DateTime.utc(2026, 1, 1),
      isShorebird: true,
      releaseVersion: '1.0.0+1',
      artifactKind: kind,
      contentHash: kind == CacheArtifactKind.release ? 'rel' : 'pat',
    );
  }

  test('release and patched zip paths differ and coexist', () async {
    final releaseZip = File(join(tempDir.path, 'src_release.zip'))
      ..writeAsStringSync('release-bytes');
    final patchedZip = File(join(tempDir.path, 'src_patched.zip'))
      ..writeAsStringSync('patched-bytes');

    await cache.updateCacheData(releaseZip, model(kind: CacheArtifactKind.release));
    await cache.updateCacheData(patchedZip, model(kind: CacheArtifactKind.patched));

    expect(
      cache.getZipCachePath('abc123', artifactKind: CacheArtifactKind.release),
      join(tempDir.path, 'abc123.release.zip'),
    );
    expect(
      cache.getZipCachePath('abc123', artifactKind: CacheArtifactKind.patched),
      join(tempDir.path, 'abc123.patched.zip'),
    );
    expect(
      await cache.isCacheExists(
        'abc123',
        artifactKind: CacheArtifactKind.release,
      ),
      isTrue,
    );
    expect(
      await cache.isCacheExists(
        'abc123',
        artifactKind: CacheArtifactKind.patched,
      ),
      isTrue,
    );
    expect(
      File(cache.getZipCachePath('abc123', artifactKind: CacheArtifactKind.release))
          .readAsStringSync(),
      'release-bytes',
    );
    expect(
      File(cache.getZipCachePath('abc123', artifactKind: CacheArtifactKind.patched))
          .readAsStringSync(),
      'patched-bytes',
    );
    expect(await manager.read(), hasLength(2));
  });

  test('legacy commit.zip is treated as release slot', () async {
    File(join(tempDir.path, 'abc123.zip')).writeAsStringSync('legacy');
    expect(
      await cache.isCacheExists(
        'abc123',
        artifactKind: CacheArtifactKind.release,
      ),
      isTrue,
    );
    expect(
      cache.resolveExistingZipCachePath(
        'abc123',
        artifactKind: CacheArtifactKind.release,
      ),
      join(tempDir.path, 'abc123.zip'),
    );
    expect(
      await cache.isCacheExists(
        'abc123',
        artifactKind: CacheArtifactKind.patched,
      ),
      isFalse,
    );
  });

  test('writing patched does not overwrite release zip', () async {
    final releaseZip = File(join(tempDir.path, 'src_release.zip'))
      ..writeAsStringSync('B0');
    await cache.updateCacheData(releaseZip, model(kind: CacheArtifactKind.release));

    final patchedZip = File(join(tempDir.path, 'src_patched.zip'))
      ..writeAsStringSync('B1');
    await cache.updateCacheData(patchedZip, model(kind: CacheArtifactKind.patched));

    expect(
      File(cache.getZipCachePath('abc123', artifactKind: CacheArtifactKind.release))
          .readAsStringSync(),
      'B0',
    );
    expect(
      File(cache.getZipCachePath('abc123', artifactKind: CacheArtifactKind.patched))
          .readAsStringSync(),
      'B1',
    );
  });
}
