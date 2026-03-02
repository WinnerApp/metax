import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dart_appwrite/dart_appwrite.dart';
import 'package:meta_tool/appwrite_server.dart';
import 'package:meta_tool/argument_get.dart';
import 'package:meta_tool/commands/first_package/first_package_config.dart';
import 'package:meta_tool/common.dart';
import 'package:path/path.dart' as p;

class FirstPackageDownloadCommand extends Command {
  @override
  String get name => 'download';

  @override
  String get description => '下载首包';

  FirstPackageDownloadCommand() {
    argParser.addOption(
      'platform',
      help: '平台',
      allowed: ['ios', 'android'],
    );
    argParser.addOption(
      'branch',
      help: '分支名称',
    );
    argParser.addOption(
      'targetDir',
      help: '下载目标目录（可选，默认使用 Assets/StreamingAssets/InnerAssets/<平台目录>）',
    );
  }

  @override
  FutureOr? run() async {
    // 1. 校验并确保配置存在，获取数据库和存储配置
    final cacheConfig = await ensureFirstPackageCacheConfig(argResults);
    final databaseId = cacheConfig['APPWRITE_ZIP_DATABASE_ID']!;
    final collectionId = cacheConfig['APPWRITE_ZIP_COLLECTION_ID']!;
    final bucketId = cacheConfig['APPWRITE_ZIP_BUCKET_ID']!;

    // 2. 选择平台
    final platform = ArgumentGet(argResults).getString(
      'platform',
      '请选择平台',
      allowed: ['ios', 'android'],
    );

    // 3. 初始化 Appwrite 客户端（从首包配置文件读取连接参数）
    final cacheEndpoint = cacheConfig['APPWRITE_ENDPOINT'];
    final cacheProjectId = cacheConfig['APPWRITE_PROJECT_ID'];
    final cacheApiKey = cacheConfig['APPWRITE_API_KEY'];

    if (cacheEndpoint == null ||
        cacheEndpoint.isEmpty ||
        cacheProjectId == null ||
        cacheProjectId.isEmpty ||
        cacheApiKey == null ||
        cacheApiKey.isEmpty) {
      throw '首包配置文件中缺少 APPWRITE_ENDPOINT / APPWRITE_PROJECT_ID / APPWRITE_API_KEY，请补充后重试';
    }

    final appwriteServer = AppwriteServer(
      endpoint: cacheEndpoint,
      projectId: cacheProjectId,
      apiKey: cacheApiKey,
    );
    final databases = Databases(appwriteServer.client);
    final storage = Storage(appwriteServer.client);

    // 4. 查询该平台下所有记录，汇总可选分支
    final allDocs = await databases.listDocuments(
      databaseId: databaseId,
      collectionId: collectionId,
      queries: [
        Query.equal('platform', platform),
        Query.orderDesc('\$createdAt'),
        Query.limit(1000),
      ],
    );

    if (allDocs.documents.isEmpty) {
      throw '当前平台 [$platform] 暂无首包记录';
    }

    final branches = <String>[];
    for (final doc in allDocs.documents) {
      final data = doc.data;
      final dynamic b = data['branch'];
      if (b is String && b.isNotEmpty && !branches.contains(b)) {
        branches.add(b);
      }
    }

    if (branches.isEmpty) {
      throw '当前平台 [$platform] 暂无可用分支记录';
    }

    // 5. 让用户选择分支
    final branch = ArgumentGet(argResults).getString(
      'branch',
      '请选择分支',
      allowed: branches,
    );

    // 6. 查询该分支最新一条记录
    final latestResult = await databases.listDocuments(
      databaseId: databaseId,
      collectionId: collectionId,
      queries: [
        Query.equal('platform', platform),
        Query.equal('branch', branch),
        Query.orderDesc('\$createdAt'),
        Query.limit(1),
      ],
    );

    if (latestResult.documents.isEmpty) {
      throw '未找到分支 [$branch] 的首包记录';
    }

    final latest = latestResult.documents.first;
    final data = latest.data;
    final dynamic fileIdsDynamic = data['fileIds'];
    if (fileIdsDynamic is! List || fileIdsDynamic.isEmpty) {
      throw '最新记录中未找到可下载的 fileIds';
    }
    final List<String> fileIds =
        fileIdsDynamic.map((e) => e.toString()).toList();

    // 7. 计算下载目标目录
    final targetDirArg = argResults?['targetDir'] as String?;
    Directory targetDir;
    if (targetDirArg != null && targetDirArg.isNotEmpty) {
      targetDir = Directory(targetDirArg);
    } else {
      final workspace = Directory.current.path;
      final platformDirName = platform == 'ios' ? 'IOS' : 'Android';
      targetDir = Directory(
        p.join(
          workspace,
          'Assets',
          'StreamingAssets',
          'InnerAssets',
          platformDirName,
        ),
      );
    }

    // 8. 如果目录已存在，先删除再重新创建，保证目录是干净的
    if (targetDir.existsSync()) {
      loggerInfo('检测到目标目录已存在，准备清理: ${targetDir.path}');
      targetDir.deleteSync(recursive: true);
    }
    targetDir.createSync(recursive: true);

    // 9. 按 MD5（fileId）缓存的目录，命中则直接拷贝，否则下载后写入缓存再拷贝
    final fileCacheDir = getFirstPackageFileCacheDir();
    if (!fileCacheDir.existsSync()) {
      fileCacheDir.createSync(recursive: true);
    }

    // 10. 下载或从缓存拷贝所有文件到目标目录
    for (final fileId in fileIds) {
      String? desiredName;
      try {
        final meta = await storage.getFile(
          bucketId: bucketId,
          fileId: fileId,
        );
        final name = (meta.name).trim();
        if (name.isNotEmpty) {
          desiredName = p.basename(name);
        }
      } catch (_) {
        // ignore: best-effort to keep original filename
      }
      desiredName ??= '$fileId.zip';

      var outPath = p.join(targetDir.path, desiredName);
      if (File(outPath).existsSync()) {
        final ext = p.extension(desiredName);
        final base = p.basenameWithoutExtension(desiredName);
        outPath = p.join(targetDir.path, '$base-$fileId$ext');
      }

      final cacheFile = File(p.join(fileCacheDir.path, fileId));
      if (cacheFile.existsSync()) {
        await cacheFile.copy(outPath);
        loggerSuccess('从缓存拷贝首包文件: ${p.basename(outPath)} (md5=$fileId)');
      } else {
        final bytes = await storage.getFileDownload(
          bucketId: bucketId,
          fileId: fileId,
        );
        await cacheFile.writeAsBytes(bytes, flush: true);
        final outFile = File(outPath);
        await outFile.writeAsBytes(bytes, flush: true);
        loggerSuccess('已下载并缓存首包文件: ${outFile.path} (md5=$fileId)');
      }
    }

    loggerSuccess(
      '首包下载完成，平台: $platform，分支: $branch，文件数: ${fileIds.length}',
    );
  }
}
