import 'dart:io';
import 'package:meta_tool/cache/framework_aar_cache.dart';
import 'package:meta_tool/commands/build/build_cache_command.dart';
import 'package:meta_tool/common.dart';
import 'package:meta_tool/define.dart';
import 'package:path/path.dart';
import 'package:process_runner/process_runner.dart';

class FlutterFrameworkCommand extends BuildCacheCommand {
  @override
  String get description => '编译Flutter Framework';

  @override
  String get name => 'flutter';

  FlutterFrameworkCommand() {
    argParser.addOption(
      'workspace',
      abbr: 's',
      help: 'flutter工程目录，默认使用当前目录',
    );
    argParser.addOption(
      'configuration',
      abbr: 'c',
      help: 'flutter工程配置，debug/release',
      allowed: ['debug', 'release'],
      mandatory: true,
    );
    argParser.addFlag(
      'clear',
      help: '是否清除缓存',
      defaultsTo: false,
    );
    argParser.addFlag(
      'publish',
      help: '是否发布',
      defaultsTo: false,
    );
  }

  late String workspace;
  late String configuration;
  late bool clear;
  late bool publish;
  @override
  Future<void> run() async {
    workspace = argResults?['workspace'] ?? Directory.current.path;
    configuration = argResults?['configuration'];
    clear = argResults?['clear'];
    publish = argResults?['publish'];
    final pubspecFile = File(join(workspace, 'pubspec.yaml'));
    if (!pubspecFile.existsSync()) {
      throw Exception('pubspec.yaml文件不存在: ${pubspecFile.path}');
    }
    if (!await isGitRepository(workspace)) {
      throw Exception('当前目录不是git仓库: $workspace');
    }

    final branch = await getCurrentBranch(workspace);
    final commitHash = await getCurrentCommitHash(workspace);
    BuildConfiguration buildConfiguration;
    if (publish) {
      buildConfiguration = BuildConfiguration.release;
    } else {
      buildConfiguration = configuration == 'debug'
          ? BuildConfiguration.debug
          : BuildConfiguration.release;
    }
    final flutterCache = FrameworkCache(
      buildConfiguration: buildConfiguration,
      buildLibrary: BuildLibrary.flutter,
      isStore: publish,
      branch: branch,
    );
    late String buildCacheDir;
    if (configuration == 'debug') {
      buildCacheDir = join(workspace, 'build', 'ios', 'framework', 'Debug');
    } else {
      buildCacheDir = join(workspace, 'build', 'ios', 'framework', 'Release');
    }
    await updateCache(
      cache: flutterCache,
      commitHash: commitHash,
      buildCacheDir: buildCacheDir,
    );
    loggerSuccess('导出Flutter Framework完成!');
  }

  @override
  Future<void> buildCache() async {
    if (clear) {
      await ProcessRunner().runProcess(
        ['flutter', 'clean'],
        workingDirectory: Directory(workspace),
        printOutput: true,
      );
    }

    /// flutter pub get
    await ProcessRunner().runProcess(
      ['flutter', 'pub', 'get'],
      workingDirectory: Directory(workspace),
      printOutput: true,
    );
    if (configuration == 'debug') {
      /// flutter build ios-framework --no-profile --no-release --xcframework --cocoapods --verbose
      await ProcessRunner().runProcess(
        [
          'flutter',
          'build',
          'ios-framework',
          '--no-profile',
          '--no-release',
          '--xcframework',
          '--cocoapods',
          '--verbose'
        ],
        workingDirectory: Directory(workspace),
        printOutput: true,
      );
    } else {
      /// flutter build ios-framework --no-debug --no-profile --xcframework --cocoapods --verbose
      await ProcessRunner().runProcess(
        [
          'flutter',
          'build',
          'ios-framework',
          '--no-debug',
          '--no-profile',
          '--xcframework',
          '--cocoapods',
          '--verbose'
        ],
        workingDirectory: Directory(workspace),
        printOutput: true,
      );
    }
  }
}
