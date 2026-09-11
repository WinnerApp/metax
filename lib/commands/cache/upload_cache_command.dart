import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dart_appwrite/dart_appwrite.dart';
import 'package:meta_tool/appwrite_environment.dart';
import 'package:meta_tool/appwrite_server.dart';
import 'package:meta_tool/argument_get.dart';
import 'package:meta_tool/cache/cache_model.dart';
import 'package:meta_tool/cache/metax_cache.dart';
import 'package:meta_tool/common.dart';
import 'package:meta_tool/define.dart';

class UploadCacheCommand extends Command {
  @override
  String get name => 'upload';

  @override
  String get description => '上传构建缓存';

  UploadCacheCommand() {
    argParser.addOption(
      'buildPlatform',
      help: '构建平台',
      allowed: BuildPlatform.values.map((e) => e.name),
    );
    argParser.addOption(
      'buildConfiguration',
      help: '构建配置',
      allowed: BuildConfiguration.values.map((e) => e.name),
    );
    argParser.addOption(
      'buildLibrary',
      help: '构建库',
      allowed: BuildLibrary.values.map((e) => e.name),
    );
    argParser.addOption(
      'buildType',
      help: '构建类型',
      allowed: BuildType.values.map((e) => e.name),
    );

    argParser.addOption(
      'branch',
      help: '分支',
    );

    argParser.addOption(
      'buildId',
      help: '构建ID',
      defaultsTo: '0',
    );

    argParser.addOption(
      'commitHash',
      help: '指定上传Hash，不指定则上传所有',
      defaultsTo: '',
    );
    argParser.addOption(
      'commitTime',
      help: 'commit时间',
    );
  }

  late AppwriteCacheEnvironment appwriteCacheEnvironment;

  @override
  FutureOr? run() async {
    appwriteCacheEnvironment = AppwriteCacheEnvironment(appHomeDir);
    String buildPlatform = ArgumentGet(argResults).getString(
      'buildPlatform',
      '请选择构建平台',
      allowed: BuildPlatform.values.map((e) => e.name).toList(),
    );

    String buildLibrary = ArgumentGet(argResults).getString(
      'buildLibrary',
      '请选择构建库',
      allowed: BuildLibrary.values.map((e) => e.name).toList(),
    );
    late String buildConfiguration;
    if (buildLibrary == BuildLibrary.flutter.name) {
      buildConfiguration = ArgumentGet(argResults).getString(
        'buildConfiguration',
        '请选择构建配置',
        allowed: BuildConfiguration.values.map((e) => e.name).toList(),
      );
    } else {
      buildConfiguration = BuildConfiguration.release.name;
    }
    String buildType = ArgumentGet(argResults).getString(
      'buildType',
      '请选择构建类型',
      allowed: BuildType.values.map((e) => e.name).toList(),
    );

    String branch = ArgumentGet(argResults).getString(
      'branch',
      '请选择分支',
    );
    int buildId = ArgumentGet(argResults).getInt(
      'buildId',
      '请选择构建ID',
      defaultValue: 0,
    );
    String commitHash = ArgumentGet(argResults).getString(
      'commitHash',
      '请选择上传Hash',
      validate: (p0) => true,
    );
    final commitTime = ArgumentGet(argResults).getString(
      'commitTime',
      '请选择commit时间',
    );

    final metaxCache = MetaxCache(
      buildPlatform:
          BuildPlatform.values.firstWhere((e) => e.name == buildPlatform),
      buildConfiguration: BuildConfiguration.values
          .firstWhere((e) => e.name == buildConfiguration),
      buildLibrary:
          BuildLibrary.values.firstWhere((e) => e.name == buildLibrary),
      buildType: BuildType.values.firstWhere((e) => e.name == buildType),
      branch: branch,
      buildId: buildId,
    );
    final cacheModels = await metaxCache.cacheManager.read();
    if (cacheModels.isEmpty) {
      loggerWarning('${metaxCache.cacheHomeDir} 缓存为空');
      return;
    }
    List<CacheModel> needUploadCommitModels = [];
    if (commitHash.isNotEmpty && await metaxCache.isCacheExists(commitHash)) {
      needUploadCommitModels = cacheModels
          .where((e) => e.commitHash == commitHash)
          .toList();
      if (needUploadCommitModels.isEmpty) {
        needUploadCommitModels = [
          CacheModel(
            buildPlatform: buildPlatform,
            buildLibrary: buildLibrary,
            buildType: buildType,
            branch: branch,
            configuration: buildConfiguration,
            commitHash: commitHash,
            buildId: buildId.toString(),
            commitTime: DateTime.parse(commitTime),
          ),
        ];
      }
    } else {
      needUploadCommitModels = cacheModels;
    }

    /// 存储上传失败的commitHash
    final failedCommitHashs = <String>[];
    for (final model in needUploadCommitModels) {
      final isUploadSuccess = await uploadCache(metaxCache, model);
      if (!isUploadSuccess) {
        failedCommitHashs.add(model.commitHash);
      }
    }
    if (failedCommitHashs.isNotEmpty) {
      loggerError('上传失败: ${failedCommitHashs.join(', ')}');
      throw Exception('缓存上传失败: ${failedCommitHashs.join(', ')}');
    }
    loggerSuccess('上传成功');
  }

  AppwriteServer _createAppwriteServer() {
    return AppwriteServer(
      endpoint: appwriteCacheEnvironment.endpoint,
      projectId: appwriteCacheEnvironment.projectId,
      apiKey: appwriteCacheEnvironment.apiKey,
    );
  }

  /// 捕获分片上传后 HttpClient keep-alive 上迟到的连接异常，避免进程被打成 exit 255
  Future<bool> _uploadInGuardedZone(Future<bool> Function() action) {
    final completer = Completer<bool>();
    runZonedGuarded(() {
      action().then((value) async {
        // 给连接层一点时间抛出迟到的 HttpException
        await Future.delayed(const Duration(milliseconds: 300));
        if (!completer.isCompleted) completer.complete(value);
      }).catchError((Object e, StackTrace stackTrace) {
        loggerError('${e.toString()} $stackTrace');
        if (!completer.isCompleted) completer.complete(false);
      });
    }, (error, stack) {
      loggerError('上传连接异常: $error\n$stack');
      if (!completer.isCompleted) completer.complete(false);
    });
    return completer.future;
  }

  Future<bool> uploadCache(MetaxCache metaxCache, CacheModel model) async {
    final probeServer = _createAppwriteServer();
    final isAlreadyUploaded = await probeServer.isCacheExists(
      databaseId: appwriteCacheEnvironment.databaseId,
      collectionId: appwriteCacheEnvironment.collectionId,
      platform: metaxCache.buildPlatform.name,
      branch: metaxCache.branch,
      buildConfiguration: metaxCache.buildConfiguration.name,
      buildLibrary: metaxCache.buildLibrary.name,
      buildType: metaxCache.buildType.name,
      buildId: metaxCache.buildId,
      commitHash: model.commitHash,
    );
    if (isAlreadyUploaded) {
      loggerInfo('缓存已存在: ${model.commitHash}');
      return true;
    }

    final zipFilePath = metaxCache.getZipCachePath(model.commitHash);
    if (!File(zipFilePath).existsSync()) {
      loggerError('缓存文件不存在: $zipFilePath');
      return false;
    }

    const maxAttempts = 3;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      final isUploadSuccess = await _uploadInGuardedZone(() {
        // 每次重试使用新 Client，避免被污染的 keep-alive 连接继续失败
        final appwriteServer = _createAppwriteServer();
        return appwriteServer.uploadCache(
          databaseId: appwriteCacheEnvironment.databaseId,
          collectionId: appwriteCacheEnvironment.collectionId,
          bucketId: appwriteCacheEnvironment.bucketId,
          platform: metaxCache.buildPlatform.name,
          branch: metaxCache.branch,
          buildConfiguration: metaxCache.buildConfiguration.name,
          buildLibrary: metaxCache.buildLibrary.name,
          buildType: metaxCache.buildType.name,
          buildId: metaxCache.buildId,
          commitHash: model.commitHash,
          commitTime: model.commitTime,
          flutterSdk: model.flutterSdk,
          isShorebird: model.isShorebird,
          releaseVersion: model.releaseVersion,
          zipFile: InputFile.fromPath(
            path: zipFilePath,
            filename: '${model.commitHash}.zip',
          ),
        );
      });
      if (isUploadSuccess) return true;
      if (attempt < maxAttempts) {
        final delay = Duration(seconds: attempt * 2);
        loggerWarning(
          '上传失败(${model.commitHash})，${delay.inSeconds}s 后重试 ($attempt/$maxAttempts)',
        );
        await Future.delayed(delay);
      }
    }
    return false;
  }
}
