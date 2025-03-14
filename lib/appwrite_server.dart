import 'dart:typed_data';

import 'package:dart_appwrite/dart_appwrite.dart';
import 'package:meta_tool/common.dart';

class AppwriteServer {
  final Client client;
  late Databases databases;

  AppwriteServer({
    required String endpoint,
    required String projectId,
    required String apiKey,
  }) : client = Client() {
    client
      ..setEndpoint(endpoint)
      ..setProject(projectId)
      ..setKey(apiKey);
    databases = Databases(client);
  }

  /// 获取当前最新分支打包版本配置
  Future<Map<String, dynamic>?> getCurrentBranchBuildConfig({
    required String databaseId,
    required String collectionId,
    required String platform,
    required String branch,
    required String unityBranch,
    required String buildName,
  }) async {
    final result = await databases.listDocuments(
      databaseId: databaseId,
      collectionId: collectionId,
      queries: [
        Query.equal('platform', platform),
        Query.equal('branch', branch),
        Query.equal('unityBranch', unityBranch),
        Query.equal('buildName', buildName),
        Query.orderDesc('\$createdAt'),
        Query.limit(1),
      ],
    ).then((e) {
      if (e.documents.isEmpty) {
        return null;
      }
      return e.documents.first;
    }).catchError((e) {
      loggerError(e.toString());
      return null;
    });
    return result?.data;
  }

  /// 更新打包版本配置
  Future<bool> updateBuildConfig({
    required String databaseId,
    required String collectionId,
    required String platform,
    required String branch,
    required String unityBranch,
    required String buildName,
    required String flutterCommitId,
    required String unityCommitId,
    required int buildNumber,
  }) async {
    return databases.createDocument(
      databaseId: databaseId,
      collectionId: collectionId,
      documentId: ID.unique(),
      data: {
        'platform': platform,
        'branch': branch,
        'unity_branch': unityBranch,
        'build_name': buildName,
        'flutter_commit_id': flutterCommitId,
        'unity_commit_id': unityCommitId,
        'build_number': buildNumber,
      },
    ).then((e) {
      return true;
    }).catchError((e) {
      loggerError(e.toString());
      return false;
    });
  }

  /// 查询缓存列表
  Future<List<Map<String, dynamic>>> queryZipCacheList({
    required String databaseId,
    required String collectionId,
    required String platform,
    required bool isStore,
    required String buildConfiguration,
    required String buildLibrary,
    required String buildType,
  }) async {
    return databases.listDocuments(
      databaseId: databaseId,
      collectionId: collectionId,
      queries: [
        Query.equal('platform', platform),
        Query.equal('is_store', isStore),
        Query.equal('configuration', buildConfiguration),
        Query.equal('library', buildLibrary),
        Query.equal('type', buildType),
      ],
    ).then((e) {
      return e.documents.map((e) => e.data).toList();
    }).catchError((e) {
      loggerError(e.toString());
      return <Map<String, dynamic>>[];
    });
  }

  /// 查询缓存是否存在
  Future<bool> isCacheExists({
    required String databaseId,
    required String collectionId,
    required String platform,
    required bool isStore,
    required String branch,
    required String buildConfiguration,
    required String buildLibrary,
    required String buildType,
    required String commitHash,
    required int buildId,
  }) async {
    return databases.listDocuments(
      databaseId: databaseId,
      collectionId: collectionId,
      queries: [
        Query.equal('platform', platform),
        Query.equal('is_store', isStore),
        Query.equal('configuration', buildConfiguration),
        Query.equal('library', buildLibrary),
        Query.equal('type', buildType),
        Query.equal('branch', branch),
        Query.equal('build_id', buildId),
        Query.equal('commit_hash', commitHash),
      ],
    ).then((e) {
      return e.documents.isNotEmpty;
    }).catchError((e) {
      loggerError(e.toString());
      return false;
    });
  }

  /// 上传缓存
  Future<bool> uploadCache({
    required String databaseId,
    required String collectionId,
    required String bucketId,
    required String platform,
    required bool isStore,
    required String branch,
    required String buildConfiguration,
    required String buildLibrary,
    required String buildType,
    required String commitHash,
    required DateTime commitTime,
    required int buildId,
    required InputFile zipFile,
  }) async {
    final Storage storage = Storage(client);
    final fileId = ID.unique();
    final isUploadSuccess = await storage
        .createFile(
      bucketId: bucketId,
      fileId: fileId,
      file: zipFile,
      onProgress: (progress) {
        loggerDebug('上传进度: ${progress.progress}%-[${zipFile.filename}]');
      },
    )
        .then((e) {
      return true;
    }).catchError((e) {
      loggerError(e.toString());
      return false;
    });
    if (!isUploadSuccess) return false;

    return databases.createDocument(
      databaseId: databaseId,
      collectionId: collectionId,
      documentId: ID.unique(),
      data: {
        'platform': platform,
        'is_store': isStore,
        'configuration': buildConfiguration,
        'library': buildLibrary,
        'type': buildType,
        'branch': branch,
        'build_id': buildId,
        'commit_hash': commitHash,
        'file_id': fileId,
        'commit_time': commitTime.toUtc().toIso8601String(),
      },
    ).then((e) {
      return true;
    }).catchError((e) {
      loggerError(e.toString());
      storage.deleteFile(bucketId: bucketId, fileId: fileId);
      return false;
    });
  }

  Future<Uint8List> downloadFile({
    required String bucketId,
    required String fileId,
  }) async {
    final Storage storage = Storage(client);
    final data =
        await storage.getFileDownload(bucketId: bucketId, fileId: fileId);
    return data;
  }
}
