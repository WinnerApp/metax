import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dart_appwrite/dart_appwrite.dart';
import 'package:meta_tool/appwrite_environment.dart';
import 'package:meta_tool/appwrite_server.dart';
import 'package:meta_tool/argument_get.dart';
import 'package:meta_tool/cache/metax_cache.dart';
import 'package:meta_tool/common.dart';
import 'package:meta_tool/define.dart';

class UploadCacheCommand extends Command {
  @override
  String get name => 'cache';

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
    );
  }

  late AppwriteEnvironment appwriteEnvironment;

  late String databaseId;
  late String collectionId;
  late String bucketId;

  @override
  FutureOr? run() async {
    appwriteEnvironment = AppwriteEnvironment();
    databaseId = readEnv('APPWRITE_ZIP_DATABASE_ID');
    collectionId = readEnv('APPWRITE_ZIP_COLLECTION_ID');
    bucketId = readEnv('APPWRITE_ZIP_BUCKET_ID');
    String buildPlatform = ArgumentGet(argResults).getString(
      'buildPlatform',
      allowed: BuildPlatform.values.map((e) => e.name).toList(),
    );
    String buildConfiguration = ArgumentGet(argResults).getString(
      'buildConfiguration',
      allowed: BuildConfiguration.values.map((e) => e.name).toList(),
    );
    String buildLibrary = ArgumentGet(argResults).getString(
      'buildLibrary',
      allowed: BuildLibrary.values.map((e) => e.name).toList(),
    );
    String buildType = ArgumentGet(argResults).getString(
      'buildType',
      allowed: BuildType.values.map((e) => e.name).toList(),
    );
    bool isStore = ArgumentGet(argResults).getString(
          'isStore',
          allowed: ['true', 'false'],
        ) ==
        'true';
    String branch = ArgumentGet(argResults).getString('branch');
    int buildId = ArgumentGet(argResults).getInt('buildId', defaultValue: 0);
    String commitHash = ArgumentGet(argResults).getString(
      'commitHash',
      validate: (p0) => true,
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
    List<String> commitHashs = cacheModels.map((e) => e.commitHash).toList();
    if (commitHashs.isEmpty) {
      throw '${metaxCache.cacheManager.cacheHome} 缓存为空';
    }
    List<String> commitHashsToUpload = [];
    if (commitHash.isNotEmpty && await metaxCache.isCacheExists(commitHash)) {
      commitHashsToUpload = [commitHash];
    } else {
      commitHashsToUpload = commitHashs;
    }

    /// 存储上传失败的commitHash
    final failedCommitHashs = [];
    for (var commitHash in commitHashsToUpload) {
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

  Future<bool> uploadCache(MetaxCache metaxCache, String commitHash) async {
    final AppwriteServer appwriteServer = AppwriteServer(
      endpoint: appwriteEnvironment.endpoint,
      projectId: appwriteEnvironment.projectId,
      apiKey: appwriteEnvironment.apiKey,
    );

    final isAlreadyUploaded = await metaxCache.isCacheExists(commitHash);
    if (isAlreadyUploaded) {
      loggerInfo('缓存已存在: $commitHash');
      return true;
    }

    final zipFilePath = await metaxCache.getZipCachePath(commitHash);
    return await appwriteServer.uploadCache(
      databaseId: databaseId,
      collectionId: collectionId,
      bucketId: bucketId,
      platform: metaxCache.buildPlatform.name,
      isStore: metaxCache.isStore,
      branch: metaxCache.branch,
      buildConfiguration: metaxCache.buildConfiguration.name,
      buildLibrary: metaxCache.buildLibrary.name,
      buildType: metaxCache.buildType.name,
      buildId: metaxCache.buildId,
      commitHash: commitHash,
      zipFile: InputFile.fromBytes(
        bytes: File(zipFilePath).readAsBytesSync(),
        filename: '$commitHash.zip',
      ),
    );
  }
}
