import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:crypto/crypto.dart';
import 'package:dart_appwrite/dart_appwrite.dart';
import 'package:meta_tool/appwrite_server.dart';
import 'package:meta_tool/argument_get.dart';
import 'package:meta_tool/commands/first_package/first_package_config.dart';
import 'package:meta_tool/common.dart';
import 'package:path/path.dart' as p;

class FirstPackageUploadCommand extends Command {
  @override
  String get name => 'upload';

  @override
  String get description => '上传首包';

  FirstPackageUploadCommand() {
    argParser.addOption(
      'platform',
      help: '平台',
      allowed: ['ios', 'android', 'ohos'],
    );
    argParser.addOption(
      'branch',
      help: '分支名称',
    );

    argParser.addOption(
      'cacheDir',
      help: '首包目录',
    );
  }

  @override
  FutureOr? run() async {
    // 1. 校验并确保缓存目录配置文件存在，获取数据库和存储配置
    final cacheConfig = await ensureFirstPackageCacheConfig(argResults);
    final databaseId = cacheConfig['APPWRITE_ZIP_DATABASE_ID']!;
    final collectionId = cacheConfig['APPWRITE_ZIP_COLLECTION_ID']!;
    final bucketId = cacheConfig['APPWRITE_ZIP_BUCKET_ID']!;

    // 2. 获取平台、分支、缓存目录
    final platform = ArgumentGet(argResults).getString(
      'platform',
      '请选择平台',
      allowed: ['ios', 'android', 'ohos'],
    );
    final branch = ArgumentGet(argResults).getString(
      'branch',
      '请输入分支名称',
    );
    final cacheDirArg = ArgumentGet(argResults).getString(
      'cacheDir',
      '请输入首包目录',
    );

    Directory cacheDir = Directory(cacheDirArg);

    if (!await cacheDir.exists()) {
      throw '首包缓存目录不存在: ${cacheDir.path}';
    }

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
    final storage = Storage(appwriteServer.client);
    final databases = Databases(appwriteServer.client);

    // 4. 遍历目录下的 zip 文件，按 md5 去重上传，并收集所有 fileId
    final List<String> fileIds = [];
    await for (final entity in cacheDir.list()) {
      if (entity is! File) {
        continue;
      }
      final lowerPath = entity.path.toLowerCase();
      if (!lowerPath.endsWith('.zip') && !lowerPath.endsWith('.bytes')) {
        continue;
      }

      final file = entity;
      final bytes = await file.readAsBytes();
      final md5Hash = md5.convert(bytes).toString();

      // 使用 md5 作为 fileId，通过 bucket 查询是否已存在
      String fileId = md5Hash;
      bool exists = true;
      try {
        await storage.getFile(
          bucketId: bucketId,
          fileId: fileId,
        );
      } catch (_) {
        exists = false;
      }

      if (exists) {
        loggerSuccess(
          '[${p.basename(file.path)}][$md5Hash] 已存在，跳过上传',
        );
      } else {
        await storage.createFile(
          bucketId: bucketId,
          fileId: fileId,
          file: InputFile.fromBytes(
            bytes: bytes,
            filename: p.basename(file.path),
          ),
          onProgress: (progress) {
            loggerDebug(
              '上传进度: ${progress.progress}%-[${file.path}]',
            );
          },
        );
        loggerSuccess(
          '[${p.basename(file.path)}][$md5Hash] 上传完成，fileId=$fileId',
        );
      }
      fileIds.add(fileId);
    }

    // 5. 全部上传完毕后，创建一条记录，包含本次所有 fileIds
    if (fileIds.isNotEmpty) {
      await databases.createDocument(
        databaseId: databaseId,
        collectionId: collectionId,
        documentId: ID.unique(),
        data: {
          'branch': branch,
          'platform': platform,
          'fileIds': fileIds,
        },
      );
    }

    loggerSuccess('首包上传流程完成');

    // 6. 若配置了首包飞书通知链接，则按平台发送通知
    final notifyUrlKey = switch (platform) {
      'ios' => firstPackageIosNotifyUrlKey,
      'android' => firstPackageAndroidNotifyUrlKey,
      'ohos' => firstPackageOhosNotifyUrlKey,
      _ => null,
    };
    final notifyUrl =
        notifyUrlKey == null ? null : cacheConfig[notifyUrlKey]?.trim();
    if (notifyUrl != null && notifyUrl.isNotEmpty) {
      final platformLabel = switch (platform) {
        'ios' => 'iOS',
        'android' => 'Android',
        'ohos' => 'OHOS',
        _ => platform,
      };
      final msg = '【首包上传成功】\n平台：$platformLabel\n分支：$branch\n文件数：${fileIds.length}';
      try {
        await sendTextToWeixinWebhooks(msg, notifyUrl);
        loggerSuccess('已发送首包上传通知到飞书');
      } catch (e) {
        loggerWarning('首包飞书通知发送失败: $e');
      }
    }
  }
}
