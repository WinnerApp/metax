import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dart_appwrite/dart_appwrite.dart';
import 'package:darty_json_safe/darty_json_safe.dart';
import 'package:meta_tool/app_home_dir.dart';
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
      'workspace',
      help: 'app运行目录',
      defaultsTo: Directory.current.path,
    );
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
      'isStore',
      help: '是否发布版本',
      allowed: ['true', 'false'],
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
    final workspace = argResults?['workspace'];
    appwriteCacheEnvironment = AppwriteCacheEnvironment(AppHomeDir(workspace));
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
    bool isStore = Unwrap(ArgumentGet(argResults).getString(
      'isStore',
      '是否应用市场的Flutter AAR',
      allowed: ['true', 'false'],
    )).map((e) => e == 'true').defaultValue(false);
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
      isStore: isStore,
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
      needUploadCommitModels = [
        CacheModel(
          buildPlatform: buildPlatform,
          buildLibrary: buildLibrary,
          buildType: buildType,
          branch: branch,
          configuration: buildConfiguration,
          commitHash: commitHash,
          buildId: buildId.toString(),
          isStore: isStore,
          commitTime: DateTime.parse(commitTime),
        ),
      ];
    } else {
      needUploadCommitModels = cacheModels;
    }

    /// 存储上传失败的commitHash
    final failedCommitHashs = [];
    for (var commitHash in needUploadCommitModels) {
      final isUploadSuccess = await uploadCache(metaxCache, commitHash);
      if (!isUploadSuccess) {
        failedCommitHashs.add(commitHash);
      }
    }
    if (failedCommitHashs.isNotEmpty) {
      loggerError('上传失败: ${failedCommitHashs.join(', ')}');
    } else {
      loggerSuccess('上传成功');
    }
  }

  Future<bool> uploadCache(MetaxCache metaxCache, CacheModel model) async {
    final AppwriteServer appwriteServer = AppwriteServer(
      endpoint: appwriteCacheEnvironment.endpoint,
      projectId: appwriteCacheEnvironment.projectId,
      apiKey: appwriteCacheEnvironment.apiKey,
    );

    final isAlreadyUploaded = await appwriteServer.isCacheExists(
      databaseId: appwriteCacheEnvironment.databaseId,
      collectionId: appwriteCacheEnvironment.collectionId,
      platform: metaxCache.buildPlatform.name,
      isStore: metaxCache.isStore,
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
    return await appwriteServer.uploadCache(
      databaseId: appwriteCacheEnvironment.databaseId,
      collectionId: appwriteCacheEnvironment.collectionId,
      bucketId: appwriteCacheEnvironment.bucketId,
      platform: metaxCache.buildPlatform.name,
      isStore: metaxCache.isStore,
      branch: metaxCache.branch,
      buildConfiguration: metaxCache.buildConfiguration.name,
      buildLibrary: metaxCache.buildLibrary.name,
      buildType: metaxCache.buildType.name,
      buildId: metaxCache.buildId,
      commitHash: model.commitHash,
      commitTime: model.commitTime,
      zipFile: InputFile.fromBytes(
        bytes: File(zipFilePath).readAsBytesSync(),
        filename: '${model.commitHash}.zip',
      ),
    );
  }
}
