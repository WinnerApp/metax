import 'dart:io';

import 'package:meta_tool/commands/patch/patch_artifact_cache.dart';
import 'package:meta_tool/define.dart';
import 'package:path/path.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('metax_patch_artifact_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('android 补丁产物目录与 flutter aar 打包一致', () {
    final flutterDir = Directory(join(tempDir.path, 'metaapp_flutter'))
      ..createSync();
    final target = resolveFlutterPatchArtifactCacheTarget(
      flutterDir: flutterDir,
      otaPlatform: 'android',
      branch: 'develop',
    );
    expect(target.buildCacheDir, join(flutterDir.path, 'build', 'host'));
    expect(target.buildPlatform, BuildPlatform.android);
    expect(target.buildType, BuildType.aar);
    expect(target.cache.buildLibrary, BuildLibrary.flutter);
  });

  test('ios 补丁产物目录与 flutter framework 打包一致', () {
    final flutterDir = Directory(join(tempDir.path, 'metaapp_flutter'))
      ..createSync();
    final target = resolveFlutterPatchArtifactCacheTarget(
      flutterDir: flutterDir,
      otaPlatform: 'ios',
      branch: 'develop',
    );
    expect(
      target.buildCacheDir,
      join(flutterDir.path, 'build', 'ios', 'framework', 'Release'),
    );
    expect(target.buildPlatform, BuildPlatform.ios);
    expect(target.buildType, BuildType.framework);
  });

  test('未知平台抛错', () {
    expect(
      () => resolveFlutterPatchArtifactCacheTarget(
        flutterDir: tempDir,
        otaPlatform: 'ohos',
        branch: 'develop',
      ),
      throwsException,
    );
  });
}
