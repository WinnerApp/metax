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
  })  : unityWorkspace = readEnv('UNITY_WORKSPACE'),
        iosUnityPath = readEnv('IOS_UNITY_PATH'),
        androidUnityPath = readEnv('ANDROID_UNITY_PATH'),
        unityEnginePath = readEnv('UNITY_ENGINE_PATH'),
        iosHookUrl = readEnv('IOS_HOOK_URL'),
        androidHookUrl = readEnv('ANDROID_HOOK_URL'),
        appStoreConnectApiKeyFilepath =
            readEnv('APP_STORE_CONNECT_API_KEY_FILEPATH'),
        appStoreConnectApiKeyId = readEnv('APP_STORE_CONNECT_API_KEY_ID'),
        appStoreConnectApiIssuerId = readEnv('APP_STORE_CONNECT_API_ISSUER_ID'),
        appIdentifier = readEnv('APP_IDENTIFIER'),
        appId = readEnv('APP_ID'),
        appwriteBuildEnvironment = AppwriteBuildEnvironment(),
        sentryUrl = readEnv('SENTRY_URL'),
        sentryAuthToken = readEnv('SENTRY_AUTH_TOKEN'),
        sentryOrg = readEnv('SENTRY_ORG'),
        sentryProject = readEnv('SENTRY_PROJECT'),
        sentryDist = readEnv('SENTRY_DIST'),
        zealotEndpoint = readEnv('ZEALOT_ENDPOINT'),
        zealotToken = readEnv('ZEALOT_TOKEN'),
        zealotChannelKey = readEnv('ZEALOT_CHANNEL_KEY'),
        umengAppKey = readEnv('UMENG_APPKEY'),
        umengMessageSecret = readEnv('UMENG_MESSAGE_SECRET'),
        umengChannel = readEnv('UMENG_CHANNEL');

  factory UploadAppEnvironment.fromEnvironment() {
    final isStore = readEnv('IS_STORE') == 'true';

    return UploadAppEnvironment(
      platform: readEnv('PLATFORM'),
      workspace: readEnv('WORKSPACE'),
      buildName: readEnv('BUILD_NAME'),
      branch: readEnv('BRANCH'),
      forceBuild: readEnv('FORCE_BUILD') == 'true',
      unityBranchName: readEnv('UNITY_BRANCH_NAME'),
      upload: readEnv('UPLOAD') == 'true',
      sendLog: readEnv('SEND_LOG') == 'true',
      isStore: isStore,
      tag: _autoTag(isStore),
      buildNumber: _autoBuildNumber(),
      iosBranch: readEnv('IOS_BRANCH'),
      androidBranch: readEnv('ANDROID_BRANCH'),
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
