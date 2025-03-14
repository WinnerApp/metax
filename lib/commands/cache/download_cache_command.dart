import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:meta_tool/app_home_dir.dart';
import 'package:meta_tool/appwrite_environment.dart';
import 'package:meta_tool/appwrite_server.dart';
import 'package:meta_tool/argument_get.dart';
import 'package:meta_tool/cache/cache_model.dart';
import 'package:meta_tool/cache/metax_cache.dart';
import 'package:meta_tool/common.dart';
import 'package:meta_tool/define.dart';
import 'package:prompts/prompts.dart' as prompts;

class DownloadCacheCommand extends Command {
  @override
  String get name => 'download';

  @override
  String get description => '下载缓存';

  DownloadCacheCommand() {
    argParser.addOption(
      'workspace',
      help: 'App工作区,默认为当前目录',
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
  }

  late AppwriteEnvironment appwriteEnvironment;
  late String databaseId;
  late String collectionId;
  late String bucketId;

  @override
  FutureOr? run() async {
    final workspace = argResults?['workspace'];
    final appHomeDir = AppHomeDir(workspace: workspace);
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
    final appwriteServer = AppwriteServer(
      endpoint: appwriteEnvironment.endpoint,
      projectId: appwriteEnvironment.projectId,
      apiKey: appwriteEnvironment.apiKey,
    );
    final cacheDocuments = await appwriteServer.queryZipCacheList(
      databaseId: databaseId,
      collectionId: collectionId,
      platform: buildPlatform,
      isStore: isStore,
      buildConfiguration: buildConfiguration,
      buildLibrary: buildLibrary,
      buildType: buildType,
      branch: branch,
    );
    if (cacheDocuments.isEmpty) {
      throw '网络缓存为空';
    }
    final builds =
        cacheDocuments.map((e) => e.data['build_id'].toString()).toList();
    String buildId;
    if (builds.length == 1) {
      buildId = builds.first;
    } else {
      buildId = prompts.choose('请选择构建ID', builds) ?? builds.first;
    }

    final commitHashs = cacheDocuments
        .where((e) => e.data['build_id'].toString() == buildId)
        .map((e) => e.data['commit_hash'].toString())
        .toList();
    if (commitHashs.isEmpty) {
      throw '构建[$buildId]不存在缓存记录!';
    }
    String commitHash;
    if (commitHashs.length == 1) {
      commitHash = commitHashs.first;
    } else {
      commitHash = prompts.choose('请选择提交哈希', commitHashs) ?? commitHashs.first;
    }
    final cacheDocument = cacheDocuments
        .firstWhere((e) => e.data['commit_hash'].toString() == commitHash);
    final fileId = cacheDocument.data['file_id'].toString();
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
      buildId: int.parse(buildId),
    );
    final cacheModel =
        await metaxCache.cacheManager.getCacheByCommitHash(commitHash);
    final cacheFile = metaxCache.getZipCachePath(commitHash);
    final cacheHomeDir = Directory(metaxCache.cacheHomeDir);
    if (!cacheHomeDir.existsSync()) {
      cacheHomeDir.createSync(recursive: true);
    }
    if (cacheModel == null) {
      await metaxCache.cacheManager.appendCache(
        CacheModel(
          buildPlatform: buildPlatform,
          buildLibrary: buildLibrary,
          buildType: buildType,
          branch: branch,
          configuration: buildConfiguration,
          commitHash: commitHash,
          buildId: buildId,
          isStore: isStore,
        ),
      );
      loggerDebug('写入配置到本地!');
    }
    if (!await metaxCache.isCacheExists(commitHash)) {
      loggerDebug('下载缓存到本地!');
      final data = await appwriteServer.downloadFile(
        bucketId: bucketId,
        fileId: fileId,
      );
      final file = File(cacheFile);
      if (!file.existsSync()) {
        await file.create(recursive: true);
      }
      await file.writeAsBytes(data);
    }
    loggerSuccess('下载缓存成功!');
    loggerDebug('使用缓存!');
    await useCache(
      workspace: appHomeDir.workspace,
      buildPlatform: BuildPlatform.values.firstWhere(
        (e) => e.name == buildPlatform,
      ),
      buildLibrary: BuildLibrary.values.firstWhere(
        (e) => e.name == buildLibrary,
      ),
      buildConfiguration: BuildConfiguration.values.firstWhere(
        (e) => e.name == buildConfiguration,
      ),
      buildType: BuildType.values.firstWhere(
        (e) => e.name == buildType,
      ),
      isStore: isStore,
      branch: branch,
      commitHash: commitHash,
      buildId: int.parse(buildId),
    );
  }
}
