import 'dart:io';

import 'package:meta_tool/commands/upload/upload_app_command.dart';
import 'package:meta_tool/common.dart';
import 'package:meta_tool/define.dart';
import 'package:meta_tool/upload_app_environment.dart';
import 'package:path/path.dart';
import 'package:process_runner/process_runner.dart';

class BuildUploadOhosCommand extends UploadAppCommand {
  @override
  String get platform => 'ohos';

  @override
  String get description => '一键打包鸿蒙 .app 并上传 AppGallery Connect';

  @override
  String get name => 'build_upload_ohos';

  @override
  String get buildType => 'library';

  BuildUploadOhosCommand() {
    argParser.addFlag(
      'formal',
      help: '走正式发布审核（默认测试分发）',
      defaultsTo: false,
      negatable: false,
    );
    argParser.addFlag(
      'skip-submit',
      help: '仅打包并上传，不提交审核',
      defaultsTo: false,
      negatable: false,
    );
  }

  bool get _formal => argResults?['formal'] as bool? ?? false;

  bool get _skipSubmit => argResults?['skip-submit'] as bool? ?? false;

  @override
  Future<void> buildApp() async {
    await ProcessRunner().runProcess(
      [
        'metax',
        'build',
        'app',
        'ohos',
        getUseMockCommand(),
      ],
      workingDirectory: appHomeDir.directory,
      printOutput: true,
    );
  }

  @override
  Future<void> uploadApp({
    required String log,
    required UploadAppEnvironment environment,
  }) async {
    final commands = <String>[
      'metax',
      'upload',
      'ohos',
      getUseMockCommand(),
    ];
    if (_formal) {
      commands.add('--formal');
    }
    if (_skipSubmit) {
      commands.add('--skip-submit');
    }
    final appPath = _findLatestOhosApp();
    if (appPath != null) {
      commands.addAll(['--app', appPath]);
    }
    await buildAppRunner.runProcess(
      commands,
      workingDirectory: appHomeDir.directory,
      printOutput: true,
    );
  }

  String? _findLatestOhosApp() {
    final ohosDir = appHomeDir.ohosDir;
    if (!ohosDir.existsSync()) {
      return null;
    }
    File? latest;
    DateTime? latestModified;
    for (final entity in ohosDir.listSync(recursive: true)) {
      if (entity is! File) {
        continue;
      }
      if (!entity.path.endsWith('.app')) {
        continue;
      }
      final modified = entity.lastModifiedSync();
      if (latest == null ||
          latestModified == null ||
          modified.isAfter(latestModified)) {
        latest = entity;
        latestModified = modified;
      }
    }
    return latest?.path;
  }

  @override
  Future<void> copyIpaOrApkToBuildDir(
    UploadAppEnvironment environment,
    String? copyDir,
  ) async {
    final appPath = _findLatestOhosApp();
    if (appPath == null) {
      loggerWarning('未找到鸿蒙 .app 产物，跳过复制');
      return;
    }
    final channel = 'AppGallery';
    final buildName = environment.buildName;
    final buildNumber = environment.buildNumber.toString();
    copyDir = copyDir ??
        join(
          environment.workspace,
          'ignore_dir',
          'ohos',
          'app',
        );
    if (!await Directory(copyDir).exists()) {
      await Directory(copyDir).create(recursive: true);
    }
    await copyFile(
      File(appPath),
      File(join(copyDir, '${channel}_${buildName}_$buildNumber.app')),
    );
  }

  @override
  Future<void> sendLog({
    required String log,
    required UploadAppEnvironment environment,
  }) async {
    await sendTextToWeixinWebhooks(log, environment.ohosHookUrl);
  }
}
