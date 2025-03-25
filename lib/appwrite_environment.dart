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

class AppwriteCacheEnvironment extends AppwriteEnvironment {
  late String databaseId;
  late String collectionId;
  late String bucketId;

  AppwriteCacheEnvironment() : super() {
    databaseId = readEnv('APPWRITE_ZIP_DATABASE_ID');
    collectionId = readEnv('APPWRITE_ZIP_COLLECTION_ID');
    bucketId = readEnv('APPWRITE_ZIP_BUCKET_ID');
  }
}

class AppwriteBuildEnvironment extends AppwriteEnvironment {
  late String databaseId;
  late String collectionId;

  AppwriteBuildEnvironment() : super() {
    databaseId = readEnv('APPWRITE_BUILD_DATABASE_ID');
    collectionId = readEnv('APPWRITE_BUILD_COLLECTION_ID');
  }
}
