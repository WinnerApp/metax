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
}
