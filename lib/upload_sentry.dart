import 'dart:io';

import 'package:meta_tool/common.dart';
import 'package:meta_tool/flutter_sdk.dart';
import 'package:path/path.dart';
import 'package:process_runner/process_runner.dart';

class UploadSentrySymbols {
  final String flutterProjectPath;
  final String project;
  final String url;
  final String authToken;
  final String org;
  final String dist;
  final String release;

  const UploadSentrySymbols({
    required this.flutterProjectPath,
    required this.project,
    required this.url,
    required this.authToken,
    required this.org,
    required this.dist,
    required this.release,
  });

  Future<void> run() async {
    final sentrypropertiesFile = join(flutterProjectPath, 'sentry.properties');
    if (!await File(sentrypropertiesFile).exists()) {
      throw Exception('sentry.properties文件不存在');
    }
    final properties = await File(sentrypropertiesFile).readAsLines();
    for (var i = 0; i < properties.length; i++) {
      final property = properties[i];
      if (property.startsWith('project=')) {
        properties[i] = 'project=$project';
      } else if (property.startsWith('url=')) {
        properties[i] = 'url=$url';
      } else if (property.startsWith('auth_token=')) {
        properties[i] = 'auth_token=$authToken';
      } else if (property.startsWith('org=')) {
        properties[i] = 'org=$org';
      } else if (property.startsWith('dist=')) {
        properties[i] = 'dist=$dist';
      } else if (property.startsWith('release=')) {
        properties[i] = 'release=$release';
      }
    }
    await File(sentrypropertiesFile).writeAsString(properties.join('\n'));
    /*
    sentry-cli debug-files upload \
  --auth-token ___ORG_AUTH_TOKEN___ \
  --org ___ORG_SLUG___ \
  --project ___PROJECT_SLUG___ \
  --include-sources \
  PATH_TO_DSYMS
    */
    final projectDir = Directory(flutterProjectPath);
    final sdk = await resolveFlutterSdk(projectDir);
    await ProcessRunner().runProcess(
      [
        ...sdk.flutterCommand,
        'packages',
        'pub',
        'run',
        'sentry_dart_plugin',
      ],
      workingDirectory: projectDir,
      printOutput: true,
    );
  }
}

class UploadIosDsym {
  final String url;
  final String authToken;
  final String org;
  final String project;
  final String dsymsPath;

  UploadIosDsym({
    required this.url,
    required this.authToken,
    required this.org,
    required this.project,
    required this.dsymsPath,
  });

  /*
    sentry-cli debug-files upload \
  --auth-token ___ORG_AUTH_TOKEN___ \
  --org ___ORG_SLUG___ \
  --project ___PROJECT_SLUG___ \
  --include-sources \
  PATH_TO_
  */

  Future<void> run() async {
    await ProcessRunner().runProcess(
      [
        'sentry-cli',
        '--url',
        url,
        'debug-files',
        'upload',
        '--auth-token',
        authToken,
        '--org',
        org,
        '--project',
        project,
        '--include-sources',
        '--il2cpp-mapping',
        dsymsPath,
      ],
      printOutput: true,
    ).catchError((e, stackTrace) {
      loggerError('上传ios符号失败:${e.toString()} ${stackTrace.toString()}');
    });
  }
}

class UploadAndroidSymbols {
  final String url;
  final String authToken;
  final String org;
  final String project;
  final String symbolsPath;

  UploadAndroidSymbols({
    required this.url,
    required this.authToken,
    required this.org,
    required this.project,
    required this.symbolsPath,
  });
  /*
  sentry-cli debug-files upload \
  --auth-token ___ORG_AUTH_TOKEN___ \
  --org ___ORG_SLUG___ \
  --project ___PROJECT_SLUG___ \
  /path/to/android/symbols...
  */

  Future<void> run() async {
    await ProcessRunner().runProcess(
      [
        'sentry-cli',
        '--url',
        url,
        'debug-files',
        'upload',
        '--auth-token',
        authToken,
        '--org',
        org,
        '--project',
        project,
        symbolsPath,
      ],
      printOutput: true,
    ).catchError((e, stackTrace) {
      loggerError('上传android符号失败:${e.toString()} ${stackTrace.toString()}');
    });
  }
}
