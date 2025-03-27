import 'dart:io';

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
    await ProcessRunner().runProcess(
      [
        'flutter',
        'packages',
        'pub',
        'run',
        'sentry_dart_plugin',
      ],
      workingDirectory: Directory(flutterProjectPath),
      printOutput: true,
    );
  }
}
