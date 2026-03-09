import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dart_appwrite/dart_appwrite.dart';
import 'package:dio/dio.dart';
import 'package:meta_tool/appwrite_environment.dart';
import 'package:meta_tool/appwrite_server.dart';
import 'package:meta_tool/argument_get.dart';
import 'package:meta_tool/cache/cache_model.dart';
import 'package:meta_tool/cache/metax_cache.dart';
import 'package:meta_tool/common.dart';
import 'package:meta_tool/define.dart';

class DownloadCacheCommand extends Command {
  @override
  String get name => 'download';

  @override
  String get description => '下载网络指定缓存';

  DownloadCacheCommand() {
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
    );

    argParser.addOption(
      'commitHash',
      help: '提交哈希',
    );
  }
  late AppwriteCacheEnvironment appwriteEnvironment;

  @override
  FutureOr? run() async {
    appwriteEnvironment = AppwriteCacheEnvironment(appHomeDir);
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

    String buildType = ArgumentGet(argResults).getString(
      'buildType',
      '请选择构建类型',
      allowed: BuildType.values.map((e) => e.name).toList(),
    );
    String buildConfiguration;
    if (buildLibrary == BuildLibrary.unity.name) {
      buildConfiguration = BuildConfiguration.release.name;
    } else {
      buildConfiguration = ArgumentGet(argResults).getString(
        'buildConfiguration',
        '请选择构建配置',
        allowed: BuildConfiguration.values.map((e) => e.name).toList(),
      );
    }

    final appwriteServer = AppwriteServer(
      endpoint: appwriteEnvironment.endpoint,
      projectId: appwriteEnvironment.projectId,
      apiKey: appwriteEnvironment.apiKey,
    );
    List<Map<String, dynamic>> cacheDocuments =
        await appwriteServer.queryZipCacheList(
      databaseId: appwriteEnvironment.databaseId,
      collectionId: appwriteEnvironment.collectionId,
      platform: buildPlatform,
      isStore: false,
      buildConfiguration: buildConfiguration,
      buildLibrary: buildLibrary,
      buildType: buildType,
    );
    if (cacheDocuments.isEmpty) {
      throw '网络缓存为空';
    }
    final branchs = cacheDocuments.map((e) => e['branch'].toString()).toList();
    String branch = ArgumentGet(argResults).getString(
      'branch',
      '请选择分支',
      allowed: branchs,
    );

    cacheDocuments =
        cacheDocuments.where((e) => e['branch'].toString() == branch).toList();

    final builds = cacheDocuments.map((e) => e['build_id'].toString()).toList();
    String buildId;
    if (builds.length == 1) {
      buildId = builds.first;
    } else {
      buildId = ArgumentGet(argResults).getString(
        'buildId',
        '请选择构建ID',
        allowed: builds,
      );
    }

    final commitHashs = cacheDocuments
        .where((e) => e['build_id'].toString() == buildId)
        .map((e) => e['commit_hash'].toString())
        .toList();
    if (commitHashs.isEmpty) {
      throw '构建[$buildId]不存在缓存记录!';
    }
    String commitHash;
    if (commitHashs.length == 1) {
      commitHash = commitHashs.first;
    } else {
      commitHash = ArgumentGet(argResults).getString(
        'commitHash',
        '请选择提交哈希',
        allowed: commitHashs,
      );
    }
    final cacheDocument = cacheDocuments
        .firstWhere((e) => e['commit_hash'].toString() == commitHash);
    final fileId = cacheDocument['file_id'].toString();
    final metaxCache = MetaxCache(
      buildPlatform:
          BuildPlatform.values.firstWhere((e) => e.name == buildPlatform),
      buildConfiguration: BuildConfiguration.values
          .firstWhere((e) => e.name == buildConfiguration),
      buildLibrary:
          BuildLibrary.values.firstWhere((e) => e.name == buildLibrary),
      buildType: BuildType.values.firstWhere((e) => e.name == buildType),
      branch: branch,
      buildId: int.parse(buildId),
    );
    // final cacheModel =
    //     await metaxCache.cacheManager.getCacheByCommitHash(commitHash);
    final cacheFile = metaxCache.getZipCachePath(commitHash);
    final cacheHomeDir = Directory(metaxCache.cacheHomeDir);
    if (!cacheHomeDir.existsSync()) {
      cacheHomeDir.createSync(recursive: true);
    }
    await metaxCache.cacheManager.appendCache(
      CacheModel(
        buildPlatform: buildPlatform,
        buildLibrary: buildLibrary,
        buildType: buildType,
        branch: branch,
        configuration: buildConfiguration,
        commitHash: commitHash,
        buildId: buildId,
        commitTime: DateTime.parse(cacheDocument['commit_time'].toString()),
      ),
    );
    loggerDebug('写入配置到本地!');
    if (!await metaxCache.isCacheExists(commitHash)) {
      loggerDebug('下载缓存到本地中，请稍等......');
      // https://appwrite.winnermedical.com/v1/storage/buckets/67d26a1b002de170d9a0/files/69a93d0fa9b0386b39d6/download?project=677f626b0012252b422e&project=677f626b0012252b422e&mode=admin
      final downloadUrl =
          '${appwriteEnvironment.endpoint}/storage/buckets/${appwriteEnvironment.bucketId}/files/$fileId/download?project=${appwriteEnvironment.projectId}&project=${appwriteEnvironment.projectId}&mode=admin';
      loggerDebug('下载缓存地址: $downloadUrl');
      final fileInfo = await Storage(appwriteServer.client).getFile(
        bucketId: appwriteEnvironment.bucketId,
        fileId: fileId,
      );

      await Dio().download(
        downloadUrl,
        cacheFile,
        onReceiveProgress: (int count, int total) {
          loggerDebug(
              '下载缓存中，已下载: ${(count / fileInfo.sizeOriginal * 100).toStringAsFixed(2)}%');
        },
      ).catchError((e, stackTrace) {
        loggerError('下载缓存失败，${e.toString()} ${stackTrace.toString()}');
        throw e;
      });
    }
    loggerSuccess('下载缓存成功!');
  }
}
