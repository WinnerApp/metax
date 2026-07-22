import 'dart:io';

import 'package:meta_tool/app_home_dir.dart';
import 'package:meta_tool/appwrite_environment.dart';
import 'package:meta_tool/common.dart';
import 'package:meta_tool/unity_environment.dart';

class UploadAppEnvironment {
  final String platform;
  final String workspace;
  final String buildName;
  final bool forceBuild;
  final String melosBranch;
  final String unityBranchName;
  final bool upload;
  final bool sendLog;
  final bool isStore;
  final String buildNumber;
  final String androidChannel;
  final UnityEnvironment unityEnvironment;
  final String iosHookUrl;
  final String androidHookUrl;
  final String ohosHookUrl;
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

  UploadAppEnvironment({
    required this.unityEnvironment,
    required this.platform,
    required this.workspace,
    required this.buildName,
    required this.forceBuild,
    required this.melosBranch,
    required this.unityBranchName,
    required this.upload,
    required this.sendLog,
    required this.isStore,
    required this.tag,
    required this.buildNumber,
    required this.zealotChannelKey,
    required this.androidChannel,
    required AppHomeDir appHomeDir,
  })  : iosHookUrl =
            readBuildAppEnv('IOS_HOOK_URL', appHomeDir, isStore: isStore),
        androidHookUrl =
            readBuildAppEnv('ANDROID_HOOK_URL', appHomeDir, isStore: isStore),
        ohosHookUrl = _readOhosHookUrl(appHomeDir, isStore),
        appStoreConnectApiKeyFilepath = readBuildAppEnv(
            'APP_STORE_CONNECT_API_KEY_FILEPATH', appHomeDir,
            isStore: isStore),
        appStoreConnectApiKeyId = readBuildAppEnv(
            'APP_STORE_CONNECT_API_KEY_ID', appHomeDir,
            isStore: isStore),
        appStoreConnectApiIssuerId = readBuildAppEnv(
            'APP_STORE_CONNECT_API_ISSUER_ID', appHomeDir,
            isStore: isStore),
        appIdentifier =
            readBuildAppEnv('APP_IDENTIFIER', appHomeDir, isStore: isStore),
        appId = readBuildAppEnv('APP_ID', appHomeDir, isStore: isStore),
        appwriteBuildEnvironment = AppwriteBuildEnvironment(appHomeDir),
        sentryUrl = readBuildAppEnv('SENTRY_URL', appHomeDir, isStore: isStore),
        sentryAuthToken =
            readBuildAppEnv('SENTRY_AUTH_TOKEN', appHomeDir, isStore: isStore),
        sentryOrg = readBuildAppEnv('SENTRY_ORG', appHomeDir, isStore: isStore),
        sentryProject =
            readBuildAppEnv('SENTRY_PROJECT', appHomeDir, isStore: isStore),
        sentryDist = '$buildName($buildNumber)',
        zealotEndpoint =
            readBuildAppEnv('ZEALOT_ENDPOINT', appHomeDir, isStore: isStore),
        zealotToken =
            readBuildAppEnv('ZEALOT_TOKEN', appHomeDir, isStore: isStore),
        umengAppKey =
            readBuildAppEnv('UMENG_APPKEY', appHomeDir, isStore: isStore),
        umengMessageSecret = readBuildAppEnv(
          'UMENG_MESSAGE_SECRET',
          appHomeDir,
          isStore: isStore,
        ),
        umengChannel = readBuildAppEnv(
          'UMENG_CHANNEL',
          appHomeDir,
          isStore: isStore,
        );

  factory UploadAppEnvironment.choose({
    required String platform,
    required String workspace,
    required String buildName,
    required bool forceBuild,
    required String melosBranch,
    required String unityBranchName,
    required bool upload,
    required bool sendLog,
    required bool isStore,
    required AppHomeDir appHomeDir,
    required UnityEnvironment unityEnvironment,
    required String zealotChannelKey,
    required String androidChannel,
  }) {
    return UploadAppEnvironment(
      platform: platform,
      workspace: workspace,
      buildName: buildName,
      forceBuild: forceBuild,
      melosBranch: melosBranch,
      unityBranchName: unityBranchName,
      upload: upload,
      sendLog: sendLog,
      isStore: isStore,
      tag: _autoTag(isStore),
      buildNumber: _autoBuildNumber(),
      appHomeDir: appHomeDir,
      unityEnvironment: unityEnvironment,
      zealotChannelKey: zealotChannelKey,
      androidChannel: androidChannel,
    );
  }
}

String _readOhosHookUrl(AppHomeDir appHomeDir, bool isStore) {
  final environment = loadBuildAppEnvironment(appHomeDir, isStore);
  final merged = {...Platform.environment, ...environment};
  return merged['OHOS_HOOK_URL'] ??
      readBuildAppEnv('ANDROID_HOOK_URL', appHomeDir,
          environment: environment, isStore: isStore);
}

String _autoTag(bool isStore) {
  String? tag = isStore ? '[市场包]' : '[测试包]';
  if (Platform.environment['TAG'] != null) {
    tag += '[${Platform.environment['TAG']}]';
  }
  return tag;
}

String _autoBuildNumber() {
  String? buildNumber = Platform.environment['BUILD_VERSION_NUMBER'];
  buildNumber ??= getCurrentTimestamp().toString();
  return buildNumber;
}
