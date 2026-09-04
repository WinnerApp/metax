import 'dart:io';

import 'package:meta_tool/argument_get.dart';
import 'package:meta_tool/cache/cache_manager.dart';
import 'package:meta_tool/cache/cache_model.dart';
import 'package:meta_tool/cache/framework_aar_cache.dart';
import 'package:meta_tool/commands/build/build_cache_command.dart';
import 'package:meta_tool/common.dart';
import 'package:meta_tool/define.dart';
import 'package:meta_tool/flutter_sdk.dart';
import 'package:meta_tool/shorebird.dart';
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
    argParser.addFlag(
      'useShorebird',
      help: '显式启用/关闭 Shorebird（覆盖 yaml/env）',
      defaultsTo: null,
    );
    argParser.addOption(
      'releaseVersion',
      help: 'Shorebird --release-version，如 1.2.3+456',
    );
    argParser.addFlag(
      'skipBuild',
      help:
          '跳过编译与 shorebird release，仅复用本地 release/ 做 sync + podspec + 写缓存。'
          '注意：Shorebird 官方 CLI 不支持单独重传 artifacts，远端上传失败需删掉不完整 release 后重新完整 release',
      defaultsTo: false,
    );
  }

  late String configuration;
  late FlutterSdkInfo flutterSdk;
  late List<String> flutterCommand;
  late bool shorebirdEnabled;
  late bool skipBuild;
  String? shorebirdReleaseVersion;

  @override
  Future<void> run() async {
    await super.run();

    configuration = ArgumentGet(argResults).getString(
      'configuration',
      '请选择Flutter Framework构建配置',
      allowed: BuildConfiguration.values.map((e) => e.name).toList(),
    );
    skipBuild = argResults?['skipBuild'] as bool? ?? false;
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

    final shorebird = resolveUseShorebird(
      appHomeDir: appHomeDir,
      explicitUseShorebird: argResults?['useShorebird'] as bool?,
    );
    shorebirdEnabled =
        shorebird.enabled && configuration == 'release';
    if (shorebird.enabled && configuration != 'release') {
      loggerWarning(
        'Shorebird 仅支持 release，当前 configuration=$configuration，回退 flutter build',
      );
    }
    loggerInfo(
      'Shorebird: enabled=$shorebirdEnabled (${shorebird.reason})',
    );
    if (shorebirdEnabled) {
      shorebirdReleaseVersion = (argResults?['releaseVersion'] as String?)
              ?.trim()
              .isNotEmpty ==
          true
          ? (argResults?['releaseVersion'] as String).trim()
          : resolveReleaseVersionFromEnv();
      if (shorebirdReleaseVersion == null ||
          shorebirdReleaseVersion!.isEmpty) {
        throw Exception(
          '启用 Shorebird 时需要 --releaseVersion 或 '
          'SHOREBIRD_RELEASE_VERSION / BUILD_VERSION_NAME+BUILD_VERSION_NUMBER',
        );
      }
    }

    final gate = await ensureFlutterSdkReady(flutterDir);
    flutterSdk = gate.sdk;
    flutterCommand = flutterSdk.flutterCommand;

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
    final sdkFingerprint = shorebirdEnabled
        ? shorebirdFlutterSdkFingerprint(flutterSdk.fingerprint)
        : flutterSdk.fingerprint;

    if (skipBuild) {
      await _runSkipBuildPipeline(
        cache: flutterCache,
        buildCacheDir: buildCacheDir,
        commitHash: commitHash,
        commitTime: commitTime,
        flutterSdkFingerprint: sdkFingerprint,
        shorebirdResolveReason: shorebird.reason,
      );
    } else {
      await updateCache(
        cache: flutterCache,
        commitHash: commitHash,
        buildCacheDir: buildCacheDir,
        commitTime: commitTime,
        cacheId: commitHash,
        forceUpdate: forceUpdate || gate.didClean,
        flutterSdk: sdkFingerprint,
        isShorebird: shorebirdEnabled,
      );
    }
    await saveFlutterSdkFingerprint(
      projectPath: flutterDir.path,
      sdk: flutterSdk,
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

  /// --skipBuild：跳过编译与 shorebird release，只做本地 sync / podspec / 写缓存。
  ///
  /// Shorebird CLI 把 build + 远端上传绑在同一条 `shorebird release` 里，
  /// 没有官方「只上传已有产物」能力；因此这里无法替你重试 Uploading artifacts。
  Future<void> _runSkipBuildPipeline({
    required FrameworkCache cache,
    required String buildCacheDir,
    required String commitHash,
    required DateTime commitTime,
    required String flutterSdkFingerprint,
    required String shorebirdResolveReason,
  }) async {
    final started = DateTime.now();
    loggerInfo(
      '========== --skipBuild：跳过编译与 shorebird release，'
      '仅本地 sync ==========',
    );
    loggerInfo(
      'Shorebird enabled=$shorebirdEnabled ($shorebirdResolveReason), '
      'configuration=$configuration',
    );
    loggerWarning(
      'Shorebird 官方 CLI 不支持只上传、不编译；'
      '若上次卡在 Uploading artifacts，远端需删掉不完整 release 后去掉 --skipBuild 重跑完整流程',
    );

    final wantShorebird = argResults?.wasParsed('useShorebird') == true &&
        argResults!['useShorebird'] == true;
    if (wantShorebird && !shorebirdEnabled) {
      throw Exception(
        '--useShorebird 已传入，但 Shorebird 未生效（configuration=$configuration）。'
        '请使用 --configuration=release',
      );
    }

    if (shorebirdEnabled) {
      final releaseDir =
          Directory(join(appHomeDir.flutterDir.path, 'release'));
      if (!releaseDir.existsSync()) {
        throw Exception(
          '--skipBuild + Shorebird 需要本地产物目录: ${releaseDir.path}\n'
          '若目录不存在，请去掉 --skipBuild 重新完整编译。',
        );
      }
      loggerInfo(
        '开始 Shorebird sync: ${releaseDir.path} -> $buildCacheDir',
      );
      await syncShorebirdIosReleaseToFrameworkDir(appHomeDir.flutterDir);
      loggerSuccess('Shorebird sync 完成（含 rename / Flutter.podspec）');
    } else {
      loggerWarning(
        'Shorebird 未启用（$shorebirdResolveReason），'
        '--skipBuild 仅复用本地 Framework。'
        '若需要 Shorebird sync，请加 --useShorebird 且 --configuration=release',
      );
      await _ensureLocalFrameworkBuildDir();
    }

    await _runSetupIosFrameworkPodspec();

    if (!Directory(buildCacheDir).existsSync()) {
      throw Exception('产物目录不存在: $buildCacheDir');
    }

    await BuildCacheManager(buildCacheDir).write([
      CacheModel(
        buildPlatform: cache.buildPlatform.value,
        buildLibrary: cache.buildLibrary.value,
        buildType: cache.buildType.value,
        branch: cache.branch,
        configuration: cache.buildConfiguration.value,
        commitHash: commitHash,
        buildId: cache.buildId.toString(),
        commitTime: commitTime,
        flutterSdk: flutterSdkFingerprint,
        isShorebird: shorebirdEnabled,
      ),
    ]);
    await writeToCacheSystem(
      buildCacheDir: buildCacheDir,
      cache: cache,
      commitHash: commitHash,
      commitTime: commitTime,
      flutterSdk: flutterSdkFingerprint,
      isShorebird: shorebirdEnabled,
    );

    loggerInfo(
      '========== --skipBuild 完成，用时: '
      '${DateTime.now().difference(started).inSeconds}秒 ==========',
    );
  }

  Future<void> _runSetupIosFrameworkPodspec() async {
    final configurationDirName = switch (configuration) {
      'debug' => 'Debug',
      'release' => 'Release',
      _ => throw Exception('不支持的配置: $configuration'),
    };
    await ProcessRunner().runProcess(
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
        [...flutterCommand, 'pub', 'get'],
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
            ...flutterCommand,
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
      } else if (shorebirdEnabled) {
        final flutterVersion = resolveShorebirdFlutterVersion(
          flutterDir: appHomeDir.flutterDir,
          sdk: flutterSdk,
        );
        // 不要传 --cocoapods：该 flag 只生成 Flutter.podspec、不产出
        // Flutter.xcframework；Shorebird 随后会 rename
        // Flutter.xcframework → ShorebirdFlutter.xcframework 并失败。
        // 宿主 CocoaPods：sync 时再改回 Flutter.xcframework 并写
        // Flutter.podspec，由 setup_ios_framework_podspec.sh /
        // generate-podfile 以 pod 'Flutter', :path 接入。
        await runShorebirdRelease(
          flutterDir: appHomeDir.flutterDir,
          platform: 'ios-framework',
          releaseVersion: shorebirdReleaseVersion!,
          flutterVersion: flutterVersion,
          extraFlutterArgs: const [
            '--no-debug',
            '--no-profile',
            '--xcframework',
            '--no-tree-shake-icons',
          ],
        );
        await syncShorebirdIosReleaseToFrameworkDir(appHomeDir.flutterDir);
      } else {
        /// flutter build ios-framework --no-debug --no-profile --xcframework --cocoapods --verbose
        await ProcessRunner().runProcess(
          [
            ...flutterCommand,
            'build',
            'ios-framework',
            '--no-debug',
            '--no-profile',
            '--xcframework',
            '--cocoapods',
            '--no-pub',
            '--no-tree-shake-icons'
          ],
          workingDirectory: appHomeDir.flutterDir,
          printOutput: true,
        );
      }
    }
    await _runSetupIosFrameworkPodspec();
  }

  Future<void> _ensureLocalFrameworkBuildDir() async {
    final configurationDirName = switch (configuration) {
      'debug' => 'Debug',
      'release' => 'Release',
      _ => throw Exception('不支持的配置: $configuration'),
    };
    final buildCacheDir = Directory(
      join(
        appHomeDir.flutterDir.path,
        'build',
        'ios',
        'framework',
        configurationDirName,
      ),
    );
    if (!buildCacheDir.existsSync()) {
      throw Exception(
        '--skipBuild 需要本地 Framework 产物，但未找到: ${buildCacheDir.path}',
      );
    }
    loggerInfo('跳过 Flutter 编译，复用本地产物: ${buildCacheDir.path}');
  }

  Future<String> getFixIosPodfileContent() async {
    final defaultContent = r'''
platform :ios, '13.0'

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
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '13.0'
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
