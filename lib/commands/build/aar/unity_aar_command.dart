import 'dart:io';

import 'package:meta_tool/cache/cache_manager.dart';
import 'package:meta_tool/cache/framework_aar_cache.dart';
import 'package:meta_tool/commands/build/build_cache_command.dart';
import 'package:meta_tool/common.dart';
import 'package:meta_tool/define.dart';
import 'package:path/path.dart';
import 'package:process_runner/process_runner.dart';

class UnityAarCommand extends BuildCacheCommand {
  @override
  String get description => '打包unity aar（在 unityAndroid 执行 build_aar.sh）';

  @override
  String get name => 'unity';

  /// Unity Library 模块：unityAndroid/unityLibrary
  Directory get _unityLibraryDir => Directory(join(
        appHomeDir.unityAndroidDir.path,
        'unityLibrary',
      ));

  /// 稳定产物目录：build/unityLibrary/outputs/aar（上传 / 本地缓存用）
  String get _stableAarDir => join(
        appHomeDir.workspace,
        'build',
        'unityLibrary',
        'outputs',
        'aar',
      );

  /// build_aar.sh 产物：unityAndroid/unityLibrary/build/outputs/aar/unityLibrary-release.aar
  File get _gradleReleaseAar => File(join(
        _unityLibraryDir.path,
        'build',
        'outputs',
        'aar',
        'unityLibrary-release.aar',
      ));

  @override
  Future<void> run() async {
    await super.run();

    final unityAndroidDir = appHomeDir.unityAndroidDir;
    if (!unityAndroidDir.existsSync()) {
      throw Exception('unityAndroid 目录不存在: ${unityAndroidDir.path}');
    }

    final unityDir = _unityLibraryDir;
    if (!unityDir.existsSync()) {
      throw Exception(
        'unityLibrary 目录不存在: ${unityDir.path}，请先运行: metax build unity_cache android',
      );
    }
    if (useMock) {
      await copyDirToDir(
        MockType.unityAar.mockDir(appHomeDir),
        MockType.unityAar.sourceCacheDir(appHomeDir),
      );
      loggerSuccess('打包Unity AAR完成!');
      return;
    }
    final cacheManager = BuildCacheManager(unityDir.path);
    final models = await cacheManager.read();
    if (models.isEmpty) {
      throw Exception('未找到Unity缓存数据，请先运行: metax build unity_cache android');
    }
    final cache = models.first;
    final branch = cache.branch;
    final commitHash = cache.commitHash;
    final commitTime = cache.commitTime;
    final buildId = cache.buildId;
    final unityCache = AarCache(
      branch: branch,
      buildConfiguration: BuildConfiguration.release,
      buildLibrary: BuildLibrary.unity,
      buildId: int.parse(buildId),
    );
    await updateCache(
      cache: unityCache,
      commitHash: commitHash,
      buildCacheDir: _stableAarDir,
      commitTime: commitTime,
      cacheId: cache.buildId.toString(),
      forceUpdate: forceUpdate,
    );

    loggerSuccess('打包Unity AAR完成!');
    if (isUpload) {
      loggerDebug('上传缓存...');
      await uploadCacheResource(
        buildPlatform: BuildPlatform.android,
        buildLibrary: BuildLibrary.unity,
        buildConfiguration: BuildConfiguration.release,
        buildType: BuildType.aar,
        branch: branch,
        commitHash: commitHash,
        commitTime: commitTime,
        buildId: int.parse(buildId),
      );
    }
  }

  @override
  Future<void> buildCache() async {
    final unityAndroidDir = appHomeDir.unityAndroidDir;
    final unityDir = _unityLibraryDir;
    final archihiveName = 'Android_achieve.zip';
    // unityAndroid/unityLibrary/src/main/assets/LocalBundle/Zips/Android_achieve.zip
    final unityArchieveFile = File(join(
      unityDir.path,
      'src',
      'main',
      'assets',
      'LocalBundle',
      'Zips',
      archihiveName,
    ));
    final parkedArchiveFile = File(join(
      appHomeDir.workspace,
      'build',
      'unityLibrary',
      '_parked',
      archihiveName,
    ));
    final buildAarArchiveFile = File(join(
      _stableAarDir,
      archihiveName,
    ));
    if (unityArchieveFile.existsSync()) {
      loggerDebug('暂时移出 Android_achieve.zip，避免打进 AAR');
      await copyFile(unityArchieveFile, parkedArchiveFile);
      await unityArchieveFile.delete();
    }

    final buildAarScript = File(join(unityAndroidDir.path, 'build_aar.sh'));
    if (!buildAarScript.existsSync()) {
      throw Exception('build_aar.sh 不存在: ${buildAarScript.path}');
    }

    /// bash build_aar.sh（在 unityAndroid 下执行，脚本负责 JDK/NDK/gradle）
    await ProcessRunner().runProcess(
      ['bash', 'build_aar.sh'],
      workingDirectory: unityAndroidDir,
      printOutput: true,
    );

    await _collectAarOutputs();

    if (parkedArchiveFile.existsSync()) {
      loggerDebug('将 Android_achieve.zip 放回 AAR 产物目录');
      await copyFile(parkedArchiveFile, buildAarArchiveFile);
      await parkedArchiveFile.delete();
    }

    // 将 unityLibrary/libs 放到 aar 同级，随 outputs/aar 一并压缩上传；
    // 使用缓存时解压到 android/aar/unity，与 aar 同目录。
    await _copyUnityLibsBesideAar(unityDir);
  }

  /// 将 build_aar.sh 产物收集到稳定目录 build/unityLibrary/outputs/aar
  Future<void> _collectAarOutputs() async {
    final sourceAar = _gradleReleaseAar;
    if (!sourceAar.existsSync()) {
      throw Exception('未找到 AAR 产物: ${sourceAar.path}');
    }

    final targetDir = Directory(_stableAarDir);
    if (targetDir.existsSync()) {
      await targetDir.delete(recursive: true);
    }
    await targetDir.create(recursive: true);
    final targetAar = File(join(targetDir.path, basename(sourceAar.path)));
    await copyFile(sourceAar, targetAar);
    loggerDebug('已收集 AAR 到 ${targetAar.path}');
  }

  Future<void> _copyUnityLibsBesideAar(Directory unityDir) async {
    final sourceLibsDir = Directory(join(unityDir.path, 'libs'));
    if (!sourceLibsDir.existsSync()) {
      loggerWarning('unityLibrary/libs 不存在，跳过复制: ${sourceLibsDir.path}');
      return;
    }

    final targetLibsDir = Directory(join(_stableAarDir, 'libs'));
    loggerDebug('复制 unityLibrary/libs 到 AAR 同级目录: ${targetLibsDir.path}');
    await copyDirToDir(sourceLibsDir, targetLibsDir);
  }
}
