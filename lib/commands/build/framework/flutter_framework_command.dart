import 'dart:io';

import 'package:meta_tool/argument_get.dart';
import 'package:meta_tool/cache/framework_aar_cache.dart';
import 'package:meta_tool/commands/build/build_cache_command.dart';
import 'package:meta_tool/common.dart';
import 'package:meta_tool/define.dart';
import 'package:path/path.dart';
import 'package:process_runner/process_runner.dart';

class FlutterFrameworkCommand extends BuildCacheCommand {
  @override
  String get description => '编译Flutter Framework';

  @override
  String get name => 'flutter';

  FlutterFrameworkCommand() {
    argParser.addOption(
      'configuration',
      abbr: 'c',
      help: 'flutter工程配置，debug/release',
      allowed: ['debug', 'release'],
    );
    argParser.addOption(
      'branch',
      help: '分支名称,指定分支则进行切换到对应分支',
    );
  }

  late String configuration;
  @override
  Future<void> run() async {
    await super.run();

    configuration = ArgumentGet(argResults).getString(
      'configuration',
      '请选择Flutter Framework构建配置',
      allowed: BuildConfiguration.values.map((e) => e.name).toList(),
    );
    final flutterDir = appHomeDir.flutterDir;
    final pubspecFile = File(join(flutterDir.path, 'pubspec.yaml'));
    if (!pubspecFile.existsSync()) {
      throw Exception('${flutterDir.path} 不是一个Flutter工程');
    }
    if (!await isGitRepository(flutterDir.path)) {
      throw Exception('${flutterDir.path} 不是一个git仓库');
    }

    final argBranch = argResults?['branch'];
    if (argBranch != null) {
      /// 如果开启skipGitPull，则跳过Git操作，直接使用本地代码
      if (skipGitPull) {
        loggerInfo('跳过Git操作模式，使用本地代码');
      } else {
        await switchBranch(flutterDir.path, argBranch);
      }
    }

    final branch = await getCurrentBranch(flutterDir.path);
    final commitHash = await getCurrentCommitHash(flutterDir.path);
    final commitTime = await getCommitTime(flutterDir.path, commitHash);
    BuildConfiguration buildConfiguration;
    buildConfiguration = BuildConfiguration.values.firstWhere(
      (e) => e.name == configuration,
    );
    final flutterCache = FrameworkCache(
      buildConfiguration: buildConfiguration,
      buildLibrary: BuildLibrary.flutter,
      branch: branch,
      buildId: 0,
    );
    late String buildCacheDir;
    if (configuration == 'debug') {
      buildCacheDir =
          join(flutterDir.path, 'build', 'ios', 'framework', 'Debug');
    } else {
      buildCacheDir =
          join(flutterDir.path, 'build', 'ios', 'framework', 'Release');
    }
    await updateCache(
      cache: flutterCache,
      commitHash: commitHash,
      buildCacheDir: buildCacheDir,
      commitTime: commitTime,
      cacheId: commitHash,
      forceUpdate: forceUpdate,
    );
    loggerSuccess('导出Flutter Framework完成!');
    if (isUpload) {
      loggerDebug('上传缓存...');
      await uploadCacheResource(
        buildPlatform: BuildPlatform.ios,
        buildLibrary: BuildLibrary.flutter,
        buildConfiguration: buildConfiguration,
        buildType: BuildType.framework,
        branch: branch,
        commitHash: commitHash,
        commitTime: commitTime,
        buildId: 0,
      );
    }
  }

  @override
  Future<void> buildCache() async {
    if (useMock) {
      await copyDirToDir(
        MockType.flutterFramework.mockDir(appHomeDir),
        MockType.flutterFramework.sourceCacheDir(appHomeDir),
      );
    } else {
      /// flutter pub get
      await ProcessRunner().runProcess(
        ['flutter', 'pub', 'get'],
        workingDirectory: appHomeDir.flutterDir,
        printOutput: true,
      );

      loggerDebug('正在修复修复iOS权限错误......');
      final iosPodFile = File(join(
        appHomeDir.flutterDir.path,
        '.ios',
        'Podfile',
      ));
      if (!iosPodFile.existsSync()) {
        throw Exception('$iosPodFile文件不存在');
      }
      final fixIosPodfileContent = await getFixIosPodfileContent();
      iosPodFile.writeAsStringSync(fixIosPodfileContent);
      await ProcessRunner().runProcess(
        [
          'pod',
          'install',
          '--verbose',
        ],
        workingDirectory: Directory(join(
          appHomeDir.flutterDir.path,
          '.ios',
        )),
        printOutput: true,
      );
      if (configuration == 'debug') {
        /// flutter build ios-framework --no-profile --no-release --xcframework --cocoapods --verbose
        await ProcessRunner().runProcess(
          [
            'flutter',
            'build',
            'ios-framework',
            '--no-profile',
            '--no-release',
            '--xcframework',
            '--cocoapods',
            '--verbose'
          ],
          workingDirectory: appHomeDir.flutterDir,
          printOutput: true,
        );
      } else {
        /// flutter build ios-framework --no-debug --no-profile --xcframework --cocoapods --verbose
        await ProcessRunner().runProcess(
          [
            'flutter',
            'build',
            'ios-framework',
            '--no-debug',
            '--no-profile',
            '--xcframework',
            '--cocoapods',
            '--verbose'
          ],
          workingDirectory: appHomeDir.flutterDir,
          printOutput: true,
        );
      }
    }
    final configurationDirName = switch (configuration) {
      'debug' => 'Debug',
      'release' => 'Release',
      _ => throw Exception('不支持的配置: $configuration'),
    };
    await ProcessRunner().runProcess(
      // jenkins_ci/setup_ios_framework_podspec.sh
      [
        'bash',
        join(
          'jenkins_ci',
          'setup_ios_framework_podspec.sh',
        ),
        configurationDirName,
        join(
          appHomeDir.flutterDir.path,
          'build',
          'ios',
          'framework',
          configurationDirName,
        ),
      ],
      workingDirectory: appHomeDir.directory,
      printOutput: true,
    );
  }

  Future<String> getFixIosPodfileContent() async {
    final defaultContent = r'''
platform :ios, '12.0'

# CocoaPods analytics sends network stats synchronously affecting flutter build latency.
ENV['COCOAPODS_DISABLE_STATS'] = 'true'

project 'Runner', {
  'Debug' => :debug,
  'Profile' => :release,
  'Release' => :release,
}

def flutter_root
  generated_xcode_build_settings_path = File.expand_path(File.join('..', 'Flutter', 'Generated.xcconfig'), __FILE__)
  unless File.exist?(generated_xcode_build_settings_path)
    raise "#{generated_xcode_build_settings_path} must exist. If you're running pod install manually, make sure \"flutter pub get\" is executed first"
  end

  File.foreach(generated_xcode_build_settings_path) do |line|
    matches = line.match(/FLUTTER_ROOT\=(.*)/)
    return matches[1].strip if matches
  end
  raise "FLUTTER_ROOT not found in #{generated_xcode_build_settings_path}. Try deleting Generated.xcconfig, then run flutter pub get"
end

require File.expand_path(File.join('packages', 'flutter_tools', 'bin', 'podhelper'), flutter_root)

flutter_ios_podfile_setup

target 'Runner' do
  use_frameworks!
  flutter_install_all_ios_pods File.dirname(File.realpath(__FILE__))

  pod 'FlutterPluginRegistrant', :path => File.join('Flutter', 'FlutterPluginRegistrant'), :inhibit_warnings => true
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)
    
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '12.0'
      # You can remove unused permissions here
      # for more information: https://github.com/Baseflow/flutter-permission-handler/blob/main/permission_handler_apple/ios/Classes/PermissionHandlerEnums.h
      # e.g. when you don't need camera permission, just add 'PERMISSION_CAMERA=0'
      config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] ||= [
      '$(inherited)',
      
      ## dart: PermissionGroup.calendar
#      'PERMISSION_EVENTS=1',
      
      ## dart: PermissionGroup.calendarFullAccess
#      'PERMISSION_EVENTS_FULL_ACCESS=1',
      
      ## dart: PermissionGroup.reminders
#      'PERMISSION_REMINDERS=1',
      
      ## dart: PermissionGroup.contacts
#      'PERMISSION_CONTACTS=1',
      
      ## dart: PermissionGroup.camera
      'PERMISSION_CAMERA=1',
      
      ## dart: PermissionGroup.microphone
      'PERMISSION_MICROPHONE=1',
      
      ## dart: PermissionGroup.speech
      'PERMISSION_SPEECH_RECOGNIZER=1',
      
      ## dart: PermissionGroup.photos
      'PERMISSION_PHOTOS=1',
      
      ## The 'PERMISSION_LOCATION' macro enables the `locationWhenInUse` and `locationAlways` permission. If
      ## the application only requires `locationWhenInUse`, only specify the `PERMISSION_LOCATION_WHENINUSE`
      ## macro.
      ##
      ## dart: [PermissionGroup.location, PermissionGroup.locationAlways, PermissionGroup.locationWhenInUse]
      'PERMISSION_LOCATION=1',
#      'PERMISSION_LOCATION_WHENINUSE=0',
      
      ## dart: PermissionGroup.notification
      'PERMISSION_NOTIFICATIONS=1',
      
      ## dart: PermissionGroup.mediaLibrary
#      'PERMISSION_MEDIA_LIBRARY=1',
      
      ## dart: PermissionGroup.sensors
#      'PERMISSION_SENSORS=1',
      
      ## dart: PermissionGroup.bluetooth
#      'PERMISSION_BLUETOOTH=1',
      
      ## dart: PermissionGroup.appTrackingTransparency
#      'PERMISSION_APP_TRACKING_TRANSPARENCY=1',
      
      ## dart: PermissionGroup.criticalAlerts
#      'PERMISSION_CRITICAL_ALERTS=1',
      
      ## dart: PermissionGroup.criticalAlerts
#      'PERMISSION_ASSISTANT=1',
      ]
      
    end
  end
end
''';
    final customFixFile = File(join(
      appHomeDir.workspace,
      'fix_ios_podfile.txt',
    ));
    loggerDebug('customFixFile: ${customFixFile.path}');
    if (customFixFile.existsSync()) {
      return customFixFile.readAsStringSync();
    }
    return defaultContent;
  }
}
