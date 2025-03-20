import 'dart:io';

import 'package:meta_tool/appwrite_environment.dart';
import 'package:meta_tool/common.dart';
import 'package:path/path.dart';

class UploadAppEnvironment {
  final String platform;
  final String workspace;
  final String buildName;
  final String branch;
  final bool forceBuild;
  final String unityBranchName;
  final bool upload;
  final bool sendLog;
  final bool isStore;
  final String buildNumber;
  final String iosBranch;
  final String androidBranch;

  final String unityWorkspace;
  final String iosUnityPath;
  final String androidUnityPath;
  final String unityEnginePath;

  final String iosHookUrl;
  final String androidHookUrl;

  final String appStoreConnectApiKeyFilepath;
  final String appStoreConnectApiKeyId;
  final String appStoreConnectApiIssuerId;
  final String appIdentifier;
  final String appId;

  final AppwriteBuildEnvironment appwriteBuildEnvironment;

  final String sentryUrl;
  final String sentryAuthToken;
  final String sentryOrg;
  final String sentryProject;
  final String sentryDist;

  final String zealotEndpoint;
  final String zealotToken;
  final String zealotChannelKey;

  final String umengAppKey;
  final String umengMessageSecret;
  final String umengChannel;

  final String tag;

  String get unityProjectDir => join(
        workspace,
        platform == 'ios' ? iosUnityPath : androidUnityPath,
      );

  UploadAppEnvironment({
    required this.platform,
    required this.workspace,
    required this.buildName,
    required this.branch,
    required this.forceBuild,
    required this.unityBranchName,
    required this.upload,
    required this.sendLog,
    required this.isStore,
    required this.tag,
    required this.buildNumber,
    required this.iosBranch,
    required this.androidBranch,
    required Map<String, String> environment,
  })  : unityWorkspace = readEnv('UNITY_WORKSPACE', environment: environment),
        iosUnityPath = readEnv('IOS_UNITY_PATH', environment: environment),
        androidUnityPath =
            readEnv('ANDROID_UNITY_PATH', environment: environment),
        unityEnginePath =
            readEnv('UNITY_ENGINE_PATH', environment: environment),
        iosHookUrl = readEnv('IOS_HOOK_URL', environment: environment),
        androidHookUrl = readEnv('ANDROID_HOOK_URL', environment: environment),
        appStoreConnectApiKeyFilepath = readEnv(
            'APP_STORE_CONNECT_API_KEY_FILEPATH',
            environment: environment),
        appStoreConnectApiKeyId =
            readEnv('APP_STORE_CONNECT_API_KEY_ID', environment: environment),
        appStoreConnectApiIssuerId = readEnv('APP_STORE_CONNECT_API_ISSUER_ID',
            environment: environment),
        appIdentifier = readEnv('APP_IDENTIFIER', environment: environment),
        appId = readEnv('APP_ID', environment: environment),
        appwriteBuildEnvironment = AppwriteBuildEnvironment(),
        sentryUrl = readEnv('SENTRY_URL', environment: environment),
        sentryAuthToken =
            readEnv('SENTRY_AUTH_TOKEN', environment: environment),
        sentryOrg = readEnv('SENTRY_ORG', environment: environment),
        sentryProject = readEnv('SENTRY_PROJECT', environment: environment),
        sentryDist = readEnv('SENTRY_DIST', environment: environment),
        zealotEndpoint = readEnv('ZEALOT_ENDPOINT', environment: environment),
        zealotToken = readEnv('ZEALOT_TOKEN', environment: environment),
        zealotChannelKey =
            readEnv('ZEALOT_CHANNEL_KEY', environment: environment),
        umengAppKey = readEnv('UMENG_APPKEY', environment: environment),
        umengMessageSecret =
            readEnv('UMENG_MESSAGE_SECRET', environment: environment),
        umengChannel = readEnv('UMENG_CHANNEL', environment: environment);

  factory UploadAppEnvironment.fromEnvironment(
    Map<String, String> environment,
  ) {
    final isStore = readEnv('IS_STORE', environment: environment) == 'true';

    return UploadAppEnvironment(
      platform: readEnv('PLATFORM', environment: environment),
      workspace: readEnv('WORKSPACE', environment: environment),
      buildName: readEnv('BUILD_NAME', environment: environment),
      branch: readEnv('BRANCH', environment: environment),
      forceBuild: readEnv('FORCE_BUILD', environment: environment) == 'true',
      unityBranchName: readEnv('UNITY_BRANCH_NAME', environment: environment),
      upload: readEnv('UPLOAD', environment: environment) == 'true',
      sendLog: readEnv('SEND_LOG', environment: environment) == 'true',
      isStore: isStore,
      tag: _autoTag(isStore),
      buildNumber: _autoBuildNumber(),
      iosBranch: readEnv('IOS_BRANCH', environment: environment),
      androidBranch: readEnv('ANDROID_BRANCH', environment: environment),
      environment: environment,
    );
  }

  factory UploadAppEnvironment.choose({
    required String platform,
    required String workspace,
    required String buildName,
    required String branch,
    required String iosBranch,
    required String androidBranch,
    required bool forceBuild,
    required String unityBranchName,
    required bool upload,
    required bool sendLog,
    required bool isStore,
    required Map<String, String> environment,
  }) {
    return UploadAppEnvironment(
      platform: platform,
      workspace: workspace,
      buildName: buildName,
      branch: branch,
      forceBuild: forceBuild,
      unityBranchName: unityBranchName,
      upload: upload,
      sendLog: sendLog,
      isStore: isStore,
      tag: _autoTag(isStore),
      buildNumber: _autoBuildNumber(),
      iosBranch: iosBranch,
      androidBranch: androidBranch,
      environment: environment,
    );
  }
}

String _autoTag(bool isStore) {
  String? tag = Platform.environment['TAG'];
  tag ??= isStore ? '[市场包]' : '[测试包]';
  return tag;
}

String _autoBuildNumber() {
  String? buildNumber = Platform.environment['BUILD_NUMBER'];
  buildNumber ??= getCurrentTimestamp().toString();
  return buildNumber;
}
