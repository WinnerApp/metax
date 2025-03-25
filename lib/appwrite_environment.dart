import 'package:meta_tool/app_home_dir.dart';
import 'package:meta_tool/common.dart';

class AppwriteEnvironment {
  late String endpoint;
  late String projectId;
  late String apiKey;

  final AppHomeDir appHomeDir;

  AppwriteEnvironment(this.appHomeDir) {
    endpoint = readAppEnv('APPWRITE_ENDPOINT', appHomeDir);
    projectId = readAppEnv('APPWRITE_PROJECT_ID', appHomeDir);
    apiKey = readAppEnv('APPWRITE_API_KEY', appHomeDir);
  }
}

class AppwriteCacheEnvironment extends AppwriteEnvironment {
  late String databaseId;
  late String collectionId;
  late String bucketId;

  AppwriteCacheEnvironment(super.appHomeDir) {
    databaseId = readAppEnv('APPWRITE_ZIP_DATABASE_ID', appHomeDir);
    collectionId = readAppEnv('APPWRITE_ZIP_COLLECTION_ID', appHomeDir);
    bucketId = readAppEnv('APPWRITE_ZIP_BUCKET_ID', appHomeDir);
  }
}

class AppwriteBuildEnvironment extends AppwriteEnvironment {
  late String databaseId;
  late String collectionId;

  AppwriteBuildEnvironment(super.appHomeDir) {
    databaseId = readAppEnv('APPWRITE_BUILD_DATABASE_ID', appHomeDir);
    collectionId = readAppEnv('APPWRITE_BUILD_COLLECTION_ID', appHomeDir);
  }
}
