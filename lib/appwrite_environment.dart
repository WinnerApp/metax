import 'package:meta_tool/common.dart';

class AppwriteEnvironment {
  late String endpoint;
  late String projectId;
  late String apiKey;

  AppwriteEnvironment() {
    endpoint = readEnv('APPWRITE_ENDPOINT');
    projectId = readEnv('APPWRITE_PROJECT_ID');
    apiKey = readEnv('APPWRITE_API_KEY');
  }
}

class AppwriteCacheEnvironment {
  late String databaseId;
  late String collectionId;
  late String bucketId;

  AppwriteCacheEnvironment() {
    databaseId = readEnv('APPWRITE_ZIP_DATABASE_ID');
    collectionId = readEnv('APPWRITE_ZIP_COLLECTION_ID');
    bucketId = readEnv('APPWRITE_ZIP_BUCKET_ID');
  }
}

class AppwriteBuildEnvironment {
  late String databaseId;
  late String collectionId;
  late String bucketId;

  AppwriteBuildEnvironment() {
    databaseId = readEnv('APPWRITE_BUILD_DATABASE_ID');
    collectionId = readEnv('APPWRITE_BUILD_COLLECTION_ID');
    bucketId = readEnv('APPWRITE_BUILD_BUCKET_ID');
  }
}
