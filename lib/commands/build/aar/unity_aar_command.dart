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
  String get description => '打包unity aar';

  @override
  String get name => 'unity';

  @override
  Future<void> run() async {
    await super.run();

    final unityDir = Directory(join(
      appHomeDir.androidDir.path,
      'unityLibrary',
    ));
    if (!unityDir.existsSync()) {
      throw Exception('unityLibrary目录不存在: ${unityDir.path}');
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
    final buildCacheDir = join(
      appHomeDir.workspace,
      'build',
      'unityLibrary',
      'outputs',
      'aar',
    );
    await updateCache(
      cache: unityCache,
      commitHash: commitHash,
      buildCacheDir: buildCacheDir,
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
    final unityDir = Directory(join(
      appHomeDir.androidDir.path,
      'unityLibrary',
    ));
    final archihiveName = 'Android_achieve.zip';
    // android/unityLibrary/src/main/assets/LocalBundle/Zips/Android_achieve.zip
    final unityArchieveFile = File(join(
      unityDir.path,
      'src',
      'main',
      'assets',
      'LocalBundle',
      'Zips',
      archihiveName,
    ));
    final androidArchieveFile = File(join(
      appHomeDir.androidDir.path,
      'app',
      'src',
      'main',
      'assets',
      'LocalBundle',
      'Zips',
      archihiveName,
    ));
    final buildAarArchiveFile = File(join(
      appHomeDir.workspace,
      'build',
      'unityLibrary',
      'outputs',
      'aar',
      archihiveName,
    ));
    if (unityArchieveFile.existsSync()) {
      loggerDebug('复制Android_archieve.zip到build/unityLibrary/outputs/aar目录下');

      /// cp -rf "$local_bundle_path" "$android_dir/app/src/main/assets"
      await copyFile(
        unityArchieveFile,
        androidArchieveFile,
      );
      await unityArchieveFile.delete();
    }

    /// 修复unityLibrary 存在ndk.path 导致gradle构建失败的问题
    await fixUnityBuildGradleFile();

    /// ./gradlew unityLibrary:bundleReleaseAar
    final gradlewName = Platform.isWindows ? 'gradlew.bat' : 'gradlew';
    final gradlew = File(join(appHomeDir.androidDir.path, gradlewName));
    if (!gradlew.existsSync()) {
      throw Exception('gradlew文件不存在: ${gradlew.path}');
    }
    final result = await ProcessRunner().runProcess(
      [gradlew.absolute.path, 'unityLibrary:bundleReleaseAar'],
      workingDirectory: appHomeDir.androidDir,
      printOutput: true,
    );
    if (result.exitCode != 0) {
      loggerError('打包Unity AAR失败: ${result.stdout}');
      exit(1);
    }
    if (androidArchieveFile.existsSync()) {
      loggerDebug('复制Android_archieve.zip到build/unityLibrary/outputs/aar目录下');

      await copyFile(
        androidArchieveFile,
        buildAarArchiveFile,
      );
      await androidArchieveFile.delete();
    }
  }

  Future<void> fixUnityBuildGradleFile() async {
    final unityBuildGradleFile = File(join(
      appHomeDir.androidDir.path,
      'unityLibrary',
      'build.gradle',
    ));
    if (!unityBuildGradleFile.existsSync()) {
      throw Exception('unityBuildGradleFile不存在: ${unityBuildGradleFile.path}');
    }
    final lines = await unityBuildGradleFile.readAsLines();
    final ndkVersion = await getNdkVersion();
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.contains('ndkPath')) {
        loggerDebug('修复ndkPath: $line');
        lines[i] = '	ndkVersion "$ndkVersion"';
      }
    }
    await unityBuildGradleFile.writeAsString(lines.join('\n'));
    loggerSuccess('修复unityBuildGradleFile完成!');
  }

  /// 获取ndk版本
  Future<String> getNdkVersion() async {
    final ndkDir = readAppEnv('NDK_DIR', appHomeDir);
    if (ndkDir.isEmpty) {
      throw Exception('NDK_DIR环境变量不存在');
    }
    final sourcePropertiesFile = File(join(ndkDir, 'source.properties'));
    if (!sourcePropertiesFile.existsSync()) {
      throw Exception('sourcePropertiesFile不存在: ${sourcePropertiesFile.path}');
    }
    final lines = await sourcePropertiesFile.readAsLines();
    for (var line in lines) {
      if (line.startsWith('Pkg.Revision')) {
        return line.split('=')[1].trim();
      }
    }
    throw Exception('sourcePropertiesFile中没有找到Pkg.Revision');
  }
}
