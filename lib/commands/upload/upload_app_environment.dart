import 'dart:io';

import 'package:meta_tool/common.dart';

class UploadAppEnvironment {
  final String platform;
  late String workspace;
  late String buildName;
  late String branch;
  late bool forceBuild;
  late String unityBranchName;
  late bool upload;
  late bool sendLog;
  late bool isStore;
  late String buildNumber;

  late String unityWorkspace;
  late String iosUnityPath;
  late String androidUnityPath;
  late String unityEnginePath;

  late String iosHookUrl;
  late String androidHookUrl;

  late String appStoreConnectApiKeyFilepath;
  late String appStoreConnectApiKeyId;
  late String appStoreConnectApiIssuerId;
  late String appIdentifier;
  late String appId;

  late String appwriteEndpoint;
  late String appwriteProjectId;
  late String appwriteApiKey;
  late String appwriteDatabaseId;
  late String appwriteCollectionId;

  late String sentryUrl;
  late String sentryAuthToken;
  late String sentryOrg;
  late String sentryProject;
  late String sentryDist;

  late String zealotEndpoint;
  late String zealotToken;
  late String zealotChannelKey;

  late String umengAppKey;
  late String umengMessageSecret;
  late String umengChannel;

  late String tag;

  UploadAppEnvironment({required this.platform}) {
    workspace = readEnv('WORKSPACE');
    buildName = readEnv('BUILD_NAME');
    branch = readEnv('BRANCH');
    forceBuild = readEnv('FORCE_BUILD') == 'true';
    unityBranchName = readEnv('UNITY_BRANCH_NAME');
    upload = readEnv('UPLOAD') == 'true';
    sendLog = readEnv('SEND_LOG') == 'true';
    isStore = readEnv('IS_STORE') == 'true';

    unityWorkspace = readEnv('UNITY_WORKSPACE');
    iosUnityPath = readEnv('IOS_UNITY_PATH');
    androidUnityPath = readEnv('ANDROID_UNITY_PATH');
    unityEnginePath = readEnv('UNITY_ENGINE_PATH');

    iosHookUrl = readEnv('IOS_HOOK_URL');
    androidHookUrl = readEnv('ANDROID_HOOK_URL');

    appStoreConnectApiKeyFilepath =
        readEnv('APP_STORE_CONNECT_API_KEY_FILEPATH');
    appStoreConnectApiKeyId = readEnv('APP_STORE_CONNECT_API_KEY_ID');
    appStoreConnectApiIssuerId = readEnv('APP_STORE_CONNECT_API_ISSUER_ID');
    appIdentifier = readEnv('APP_IDENTIFIER');
    appId = readEnv('APP_ID');

    appwriteEndpoint = readEnv('APPWRITE_ENDPOINT');
    appwriteProjectId = readEnv('APPWRITE_PROJECT_ID');
    appwriteApiKey = readEnv('APPWRITE_API_KEY');
    appwriteDatabaseId = readEnv('APPWRITE_DATABASE_ID');
    appwriteCollectionId = readEnv('APPWRITE_COLLECTION_ID');

    sentryUrl = readEnv('SENTRY_URL');
    sentryAuthToken = readEnv('SENTRY_AUTH_TOKEN');
    sentryOrg = readEnv('SENTRY_ORG');
    sentryProject = readEnv('SENTRY_PROJECT');
    sentryDist = readEnv('SENTRY_DIST');

    zealotEndpoint = readEnv('ZEALOT_ENDPOINT');
    zealotToken = readEnv('ZEALOT_TOKEN');
    zealotChannelKey = readEnv('ZEALOT_CHANNEL_KEY');

    umengAppKey = readEnv('UMENG_APPKEY');
    umengMessageSecret = readEnv('UMENG_MESSAGE_SECRET');
    umengChannel = readEnv('UMENG_CHANNEL');

    String? tag = Platform.environment['TAG'];
    if (tag != null) {
      this.tag = tag;
    } else {
      this.tag = isStore ? '[市场包]' : '[测试包]';
    }

    String? buildNumber = Platform.environment['BUILD_NUMBER'];
    if (buildNumber != null) {
      this.buildNumber = buildNumber;
    } else {
      this.buildNumber =
          (DateTime.now().millisecondsSinceEpoch / 1000).toStringAsFixed(0);
    }
  }
}
