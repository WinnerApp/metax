import 'dart:io';
import 'package:darty_json_safe/darty_json_safe.dart';
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

  UnityAarCommand() {
    argParser.addOption('workspace', abbr: 's', help: '安卓目录');
  }

  late String workspace;

  @override
  Future<void> run() async {
    workspace = argResults?['workspace'] ?? Directory.current.path;
    final unityDir = Directory(join(workspace, 'unityLibrary'));
    if (!unityDir.existsSync()) {
      throw Exception('unityLibrary目录不存在: ${unityDir.path}');
    }
    final buildIdFile = File(join(unityDir.path, '.build_id'));
    if (!await buildIdFile.exists()) {
      throw Exception('build_id文件不存在: ${buildIdFile.path}');
    }
    final jsonText = await buildIdFile.readAsString().catchError((e) => '{}');
    final json = JSON(jsonText);
    final branch = json['branch'].string;
    final commitHash = json['commitHash'].string;
    if (branch == null || commitHash == null) {
      throw Exception('build_id文件格式错误: ${buildIdFile.path}');
    }
    final unityCache = AarCache(
      isStore: true,
      branch: branch,
      buildConfiguration: BuildConfiguration.release,
      buildLibrary: BuildLibrary.unity,
    );
    final buildCacheDir = join(
      Directory(workspace).parent.path,
      'build',
      'unityLibrary',
      'outputs',
      'aar',
    );
    await updateCache(
      cache: unityCache,
      commitHash: commitHash,
      buildCacheDir: buildCacheDir,
    );

    loggerSuccess('打包Unity AAR完成!');
  }

  @override
  Future<void> buildCache() async {
    final unityDir = Directory(join(workspace, 'unityLibrary'));
    final localBundleDir = Directory(join(
      unityDir.path,
      'src',
      'main',
      'assets',
      'LocalBundles',
    ));
    if (localBundleDir.existsSync()) {
      /// cp -rf "$local_bundle_path" "$android_dir/app/src/main/assets"
      await ProcessRunner().runProcess(
        ['cp', '-rf', localBundleDir.path, "$workspace/app/src/main/assets"],
        workingDirectory: Directory(workspace),
        printOutput: true,
      );
    }

    /// rm -rf "$local_bundle_path"
    await ProcessRunner().runProcess(
      ['rm', '-rf', localBundleDir.path],
      workingDirectory: Directory(workspace),
      printOutput: true,
    );

    /// ./gradlew unityLibrary:bundleReleaseAar
    await ProcessRunner().runProcess(
      ['./gradlew', 'unityLibrary:bundleReleaseAar'],
      workingDirectory: Directory(workspace),
      printOutput: true,
    );
  }
}
