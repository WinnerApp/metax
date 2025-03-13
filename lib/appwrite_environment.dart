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
