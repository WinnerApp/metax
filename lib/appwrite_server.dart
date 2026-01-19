import 'dart:typed_data';

import 'package:dart_appwrite/dart_appwrite.dart';
import 'package:dart_appwrite/models.dart';
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
  Future<Document?> getCurrentBranchBuildConfig({
    required String databaseId,
    required String buildConfigCollectionId,
    required String platform,
    required String melosBranch,
    required String unityBranch,
    required String buildName,
  }) async {
    return databases.listDocuments(
      databaseId: databaseId,
      collectionId: buildConfigCollectionId,
      queries: [
        Query.equal('platform', platform),
        Query.equal('melos_branch', melosBranch),
        Query.equal('unity_branch', unityBranch),
        Query.equal('build_name', buildName),
        Query.orderDesc('\$createdAt'),
        Query.limit(1),
      ],
    ).then((e) {
      if (e.documents.isEmpty) {
        return null;
      }
      return e.documents.first;
    }).catchError((e, stackTrace) {
      loggerError("获取当前最新分支打包版本配置失败: $e\n$stackTrace");
      throw e;
    });
  }

  /// 查询最新打包相关分支配置
  Future<DocumentList?> queryBuildBranchConfig({
    required String databaseId,
    required String buildBranchConfigCollectionId,
    required String buildId,
  }) async {
    return databases
        .listDocuments(
          databaseId: databaseId,
          collectionId: buildBranchConfigCollectionId,
          queries: [
            Query.equal('melos_build_id', buildId),
            Query.orderDesc('\$createdAt'),
          ],
        )
        .then<DocumentList?>((e) => e)
        .catchError((e, stackTrace) {
          loggerError("查询最新打包相关分支配置失败: $e\n$stackTrace");
          throw e;
        });
  }

  /// 更新打包版本配置
  Future<void> updateBuildConfig({
    required String databaseId,
    required String buildConfigCollectionId,
    required String buildBranchConfigCollectionId,
    required String platform,
    required String melosBranch,
    required String unityBranch,
    required String buildName,
    required String unityBuilderVersion,
    required String unityCommitId,
    required int buildNumber,
    required List<AppwriteBuildBranchConfig> buildBranchConfigs,
  }) async {
    final document = await databases.createDocument(
      databaseId: databaseId,
      collectionId: buildConfigCollectionId,
      documentId: ID.unique(),
      data: {
        'platform': platform,
        'melos_branch': melosBranch,
        'unity_branch': unityBranch,
        'build_name': buildName,
        'unity_build_version': unityBuilderVersion,
        'unity_commit_id': unityCommitId,
        'build_number': buildNumber.toString(),
      },
    ).catchError((e, stackTrace) {
      loggerError("创建打包版本配置失败: $e\n$stackTrace");
      throw e;
    });
    for (final config in buildBranchConfigs) {
      await databases.createDocument(
        databaseId: databaseId,
        collectionId: buildBranchConfigCollectionId,
        documentId: ID.unique(),
        data: {
          "melos_build_id": document.$id,
          "path": config.path,
          "branch": config.branch,
          "commit_id": config.commitHash,
        },
      ).catchError((e, stackTrace) {
        loggerError("创建打包分支配置失败: $e\n$stackTrace");
        throw e;
      });
    }
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
    String? buildPlatform,
  }) async {
    // 如果 buildPlatform 为 null，则默认为 'macos'
    final actualBuildPlatform = buildPlatform ?? 'macos';
    final queries = <String>[
      Query.equal('platform', platform),
      Query.equal('is_store', isStore),
      Query.equal('configuration', buildConfiguration),
      Query.equal('library', buildLibrary),
      Query.equal('type', buildType),
      Query.orderDesc('\$createdAt'),
    ];

    // 添加 buildPlatform 过滤，支持 null 值查询（兼容旧数据）
    // 如果查询的是 macos，也要查询 buildPlatform 为 null 的记录（旧数据默认是 macos）
    if (actualBuildPlatform == 'macos') {
      queries.add(Query.or([
        Query.equal('buildPlatform', 'macos'),
        Query.isNull('buildPlatform'),
      ]));
    } else {
      queries.add(Query.equal('buildPlatform', actualBuildPlatform));
    }

    return databases
        .listDocuments(
      databaseId: databaseId,
      collectionId: collectionId,
      queries: queries,
    )
        .then((e) {
      return e.documents.map((e) => e.data).toList();
    }).catchError((e, stackTrace) {
      loggerError("查询缓存列表失败: $e\n$stackTrace");
      return <Map<String, dynamic>>[];
    });
  }

  /// 查询缓存是否存在
  Future<bool> isCacheExists({
    required String databaseId,
    required String collectionId,
    required String platform,
    required String branch,
    required String buildConfiguration,
    required String buildLibrary,
    required String buildType,
    required String commitHash,
    required int buildId,
    String? buildPlatform,
  }) async {
    // 如果 buildPlatform 为 null，则默认为 'macos'
    final actualBuildPlatform = buildPlatform ?? 'macos';
    final queries = <String>[
      Query.equal('platform', platform),
      Query.equal('is_store', true),
      Query.equal('configuration', buildConfiguration),
      Query.equal('library', buildLibrary),
      Query.equal('type', buildType),
      Query.equal('branch', branch),
      Query.equal('build_id', buildId),
      Query.equal('commit_hash', commitHash),
    ];

    // 添加 buildPlatform 过滤，支持 null 值查询（兼容旧数据）
    // 如果查询的是 macos，也要查询 buildPlatform 为 null 的记录（旧数据默认是 macos）
    if (actualBuildPlatform == 'macos') {
      queries.add(Query.or([
        Query.equal('buildPlatform', 'macos'),
        Query.isNull('buildPlatform'),
      ]));
    } else {
      queries.add(Query.equal('buildPlatform', actualBuildPlatform));
    }

    return databases
        .listDocuments(
      databaseId: databaseId,
      collectionId: collectionId,
      queries: queries,
    )
        .then((e) {
      return e.documents.isNotEmpty;
    }).catchError((e, stackTrace) {
      loggerError("查询缓存是否存在失败: $e\n$stackTrace");
      return false;
    });
  }

  /// 上传缓存
  Future<bool> uploadCache({
    required String databaseId,
    required String collectionId,
    required String bucketId,
    required String platform,
    required String branch,
    required String buildConfiguration,
    required String buildLibrary,
    required String buildType,
    required String commitHash,
    required DateTime commitTime,
    required int buildId,
    required InputFile zipFile,
    String? buildPlatform,
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
    }).catchError((e, stackTrace) {
      loggerError("上传缓存文件失败: $e\n$stackTrace");
      return false;
    });
    if (!isUploadSuccess) return false;

    // 如果 buildPlatform 为 null，则默认为 'macos'
    final actualBuildPlatform = buildPlatform ?? 'macos';

    return databases.createDocument(
      databaseId: databaseId,
      collectionId: collectionId,
      documentId: ID.unique(),
      data: {
        'platform': platform,
        'is_store': false,
        'configuration': buildConfiguration,
        'library': buildLibrary,
        'type': buildType,
        'branch': branch,
        'build_id': buildId,
        'commit_hash': commitHash,
        'file_id': fileId,
        'commit_time': commitTime.toUtc().toIso8601String(),
        'buildPlatform': actualBuildPlatform,
      },
    ).then((e) {
      return true;
    }).catchError((e, stackTrace) {
      loggerError("上传缓存文档失败: $e\n$stackTrace");
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

class AppwriteBuildBranchConfig {
  final String path;
  final String branch;
  final String commitHash;

  AppwriteBuildBranchConfig({
    required this.path,
    required this.branch,
    required this.commitHash,
  });
}
