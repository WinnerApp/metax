import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:meta_tool/common.dart';
import 'package:meta_tool/define.dart';
import 'package:path/path.dart';
import 'package:process_runner/process_runner.dart';
import 'package:prompts/prompts.dart' as prompts;

class ProjectCommand extends Command {
  @override
  String get description => "初始化工程";

  @override
  String get name => "project";

  @override
  FutureOr? run() async {
    final appRunner = await createAppRunner(appHomeDir);
    final isInitIos = prompts.choose(
      '是否需要初始化IOS工程',
      ['需要', '不需要'],
    );
    if (isInitIos == '需要') {
      final iosGitUrl = readAppEnv('IOS_GIT_URL', appHomeDir);
      final iosProjectDir = appHomeDir.iosDir;
      await _initGitProject(iosProjectDir, iosGitUrl);
      final versionName = prompts.get('请输入版本号，例如1.0.0');
      final generateXcconfigContent = '''
COCOAPODS_PARALLEL_CODE_SIGN=true
FLUTTER_BUILD_NAME=$versionName
FLUTTER_BUILD_NUMBER=${getCurrentTimestamp()}
EXCLUDED_ARCHS[sdk=iphonesimulator*]=i386
EXCLUDED_ARCHS[sdk=iphoneos*]=armv7
''';

      final localGeneratedXcconfigFile = File(join(
        iosProjectDir.path,
        'Flutter',
        'Generated.xcconfig',
      ));
      await createFileAndWrite(
        localGeneratedXcconfigFile,
        generateXcconfigContent,
      );
    }

    final isInitAndroid = prompts.choose(
      '是否需要初始化Android工程',
      ['需要', '不需要'],
    );
    if (isInitAndroid == '需要') {
      final androidGitUrl = readAppEnv('ANDROID_GIT_URL', appHomeDir);
      final androidProjectDir = appHomeDir.androidDir;
      await _initGitProject(androidProjectDir, androidGitUrl);

      final keyPropertiesContent = '''
storePassword=winer2023
keyPassword=winer2023
keyAlias=upload
storeFile=${appHomeDir.workspace}/winner-metaapp-keystore.jks
''';
      final keyPropertiesFile = File(join(
        androidProjectDir.path,
        'key.properties',
      ));
      await createFileAndWrite(keyPropertiesFile, keyPropertiesContent);
      final sdkDir = readAppEnv('SDK_DIR', appHomeDir);
      final ndkDir = readAppEnv('NDK_DIR', appHomeDir);
      final versionName = prompts.get('请输入版本号，例如1.0.0');
      final localPropertiesContent = '''
sdk.dir=$sdkDir
flutterSourceCompile=false
useUnityAarBuild=true
enableRocketX=true
ndk.dir=$ndkDir
flutter.versionName=$versionName
flutter.versionCode=${getCurrentTimestamp()}
flutter.buildMode=release
flutter.compileSdkVersion=32
flutter.minSdkVersion=21
''';
      final localPropertiesFile = File(join(
        androidProjectDir.path,
        'local.properties',
      ));
      await createFileAndWrite(localPropertiesFile, localPropertiesContent);
    }

    final isInitFlutter = prompts.choose(
      '是否需要初始化Flutter工程',
      ['需要', '不需要'],
    );
    if (isInitFlutter == '需要') {
      final flutterGitUrl = appRunner.environment['FLUTTER_GIT_URL']!;
      final flutterProjectDir = appHomeDir.flutterDir;
      await _initGitProject(flutterProjectDir, flutterGitUrl);
      // await ProcessRunner().runProcess(
      //   [
      //     'metax',
      //     'init',
      //     'flutter_web_environment',
      //   ],
      //   workingDirectory: appHomeDir.directory,
      // );
      await ProcessRunner().runProcess(
        [
          'flutter',
          'pub',
          'get',
        ],
        workingDirectory: flutterProjectDir,
      );
      await ProcessRunner().runProcess(
        [
          'flutter',
          'pub',
          'run',
          'dart_define',
          'generate',
        ],
        workingDirectory: flutterProjectDir,
      );
    }
  }

  Future<void> _initGitProject(Directory projectDir, String gitUrl) async {
    if (!projectDir.existsSync()) {
      await cloneRepository(projectDir.path, gitUrl);
    }
    final branchList = await getLatestBranchList(projectDir.path);
    String? branch = prompts.choose(
      '请选择分支',
      branchList,
    );
    if (branch == null) {
      throw '分支不能为空';
    }
    await switchBranch(projectDir.path, branch);
  }
}
