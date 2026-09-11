import 'dart:io';

import 'package:meta_tool/app_home_dir.dart';
import 'package:meta_tool/common.dart';
import 'package:meta_tool/doctor.dart';
import 'package:meta_tool/flutter_sdk.dart';
import 'package:meta_tool/shorebird.dart';
import 'package:meta_tool/shorebird_doctor.dart';
import 'package:path/path.dart';

/// `metax init doctor` 预检范围。
class MetaxDoctorOptions {
  /// 要检查的平台；空 = 按工作区已有目录自动探测。
  final Set<String> platforms;

  final bool checkUnity;
  final bool checkShorebird;
  final bool checkPatch;
  final bool checkUpload;
  final bool checkNetwork;

  const MetaxDoctorOptions({
    this.platforms = const {},
    this.checkUnity = false,
    this.checkShorebird = true,
    this.checkPatch = false,
    this.checkUpload = false,
    this.checkNetwork = true,
  });
}

/// 打包机全量环境预检：CLI / 工程文件 / env / Shorebird。
class MetaxDoctor {
  final AppHomeDir appHomeDir;
  final Map<String, String> environment;
  final MetaxDoctorOptions options;

  MetaxDoctor({
    required this.appHomeDir,
    Map<String, String>? environment,
    this.options = const MetaxDoctorOptions(),
  }) : environment = Map<String, String>.from(
          environment ?? Platform.environment,
        );

  Future<DoctorReport> run() async {
    final items = <DoctorCheckItem>[];

    items.addAll(await _checkCoreTools());
    items.addAll(_checkWorkspaceLayout());
    items.addAll(_checkJenkinsEnvFiles());
    items.addAll(await _checkFlutterProject());

    final platforms = _resolvePlatforms();
    if (platforms.contains('ios')) {
      items.addAll(await _checkIos());
    }
    if (platforms.contains('android')) {
      items.addAll(await _checkAndroid());
    }
    if (platforms.contains('ohos')) {
      items.addAll(await _checkOhos());
    }

    final appEnv = _tryLoadAppEnvironment();
    if (options.checkUnity || _looksLikeUnityMachine(appEnv)) {
      items.addAll(await _checkUnity(appEnv));
    }

    if (options.checkUpload || options.checkPatch) {
      items.addAll(_checkAppwriteKeys(appEnv));
    }
    if (options.checkUpload) {
      items.addAll(_checkUploadSecrets());
    }

    if (options.checkShorebird) {
      final shorebird = await ShorebirdDoctor(
        appHomeDir: appHomeDir,
        environment: {
          ...?appEnv,
          ...environment,
        },
        checkNetwork: options.checkNetwork,
      ).run();
      // 未启用 Shorebird 时，CLI/鉴权缺失降为 warning，避免普通打包机被误杀
      final enabled = resolveUseShorebird(
        appHomeDir: appHomeDir,
        environment: {...?appEnv, ...environment},
      ).enabled;
      for (final item in shorebird.items) {
        if (!enabled &&
            !item.ok &&
            item.severity == DoctorCheckSeverity.error &&
            const {
              'shorebird_cli',
              'shorebird_auth',
              'network_api',
              'network_download',
              'shorebird_yaml',
              'flutter_version',
            }.contains(item.id)) {
          items.add(
            item.copyWith(
              severity: DoctorCheckSeverity.warning,
              detail: '${item.detail}（当前未启用 Shorebird，仅作提示）',
            ),
          );
        } else {
          items.add(item);
        }
      }
    }

    return DoctorReport(items);
  }

  Set<String> _resolvePlatforms() {
    if (options.platforms.isNotEmpty) {
      return options.platforms;
    }
    final found = <String>{};
    if (appHomeDir.iosDir.existsSync()) found.add('ios');
    if (appHomeDir.androidDir.existsSync()) found.add('android');
    if (appHomeDir.ohosDir.existsSync()) found.add('ohos');
    return found.isEmpty ? {'ios', 'android'} : found;
  }

  bool _looksLikeUnityMachine(Map<String, String>? appEnv) {
    final env = {...?appEnv, ...environment};
    return (env['UNITY_ENGINE_PATH'] ?? '').trim().isNotEmpty ||
        (env['UNITY_WORKSPACE'] ?? '').trim().isNotEmpty ||
        (env['TUANJIE_ENGINE_PATH'] ?? '').trim().isNotEmpty;
  }

  Map<String, String>? _tryLoadAppEnvironment() {
    try {
      return loadAppEnvironment(appHomeDir);
    } catch (_) {
      return null;
    }
  }

  Future<List<DoctorCheckItem>> _checkCoreTools() async {
    const group = 'core';
    final checks = <({String id, String name, String fix, DoctorCheckSeverity sev})>[
      (
        id: 'cmd_metax',
        name: 'metax',
        fix: '将 metax 可执行文件加入 PATH（Jenkins agent 非交互 shell 也要有）',
        sev: DoctorCheckSeverity.error,
      ),
      (
        id: 'cmd_git',
        name: 'git',
        fix: '安装 git',
        sev: DoctorCheckSeverity.error,
      ),
      (
        id: 'cmd_fvm',
        name: 'fvm',
        fix: '安装 FVM：dart pub global activate fvm，并保证 PATH 含 pub-cache/bin',
        sev: DoctorCheckSeverity.error,
      ),
      (
        id: 'cmd_curl',
        name: 'curl',
        fix: '安装 curl',
        sev: DoctorCheckSeverity.warning,
      ),
      (
        id: 'cmd_unzip',
        name: 'unzip',
        fix: '安装 unzip（缓存解压 / APK 渠道校验需要）',
        sev: DoctorCheckSeverity.error,
      ),
      (
        id: 'cmd_zip',
        name: 'zip',
        fix: '安装 zip（上传缓存打包需要）',
        sev: DoctorCheckSeverity.error,
      ),
      (
        id: 'cmd_bash',
        name: 'bash',
        fix: '安装 bash',
        sev: DoctorCheckSeverity.warning,
      ),
    ];

    final items = <DoctorCheckItem>[];
    for (final c in checks) {
      final path = await whichCommand(c.name, environment: environment);
      items.add(
        commandPresent(
          id: c.id,
          title: '命令 ${c.name}',
          path: path,
          fix: c.fix,
          missingSeverity: c.sev,
          group: group,
        ),
      );
    }
    return items;
  }

  List<DoctorCheckItem> _checkWorkspaceLayout() {
    const group = 'workspace';
    return [
      fileOrDirPresent(
        id: 'dir_flutter',
        title: '目录 metaapp_flutter',
        exists: appHomeDir.flutterDir.existsSync(),
        path: appHomeDir.flutterDir.path,
        fix: '在 app 仓库根目录执行，或传 --workspace=<app根>',
        group: group,
      ),
      fileOrDirPresent(
        id: 'dir_jenkins_ci',
        title: '目录 jenkins_ci',
        exists: Directory(join(appHomeDir.workspace, 'jenkins_ci')).existsSync(),
        path: join(appHomeDir.workspace, 'jenkins_ci'),
        fix: '确认 workspace 指向 app 仓库根（含 jenkins_ci/）',
        group: group,
      ),
    ];
  }

  List<DoctorCheckItem> _checkJenkinsEnvFiles() {
    const group = 'env';
    final appEnv = File(
      join(appHomeDir.workspace, 'jenkins_ci', 'env', 'app', '.env'),
    );
    final appwriteEnv = File(
      join(appHomeDir.workspace, 'jenkins_ci', 'env', 'appwrite', '.env'),
    );
    return [
      fileOrDirPresent(
        id: 'env_app',
        title: 'jenkins_ci/env/app/.env',
        exists: appEnv.existsSync(),
        path: appEnv.path,
        fix: 'metax init app_environment',
        group: group,
      ),
      fileOrDirPresent(
        id: 'env_appwrite',
        title: 'jenkins_ci/env/appwrite/.env',
        exists: appwriteEnv.existsSync(),
        path: appwriteEnv.path,
        fix: 'metax init app_environment（会合并 appwrite 环境）',
        group: group,
      ),
    ];
  }

  Future<List<DoctorCheckItem>> _checkFlutterProject() async {
    const group = 'flutter';
    final flutterDir = appHomeDir.flutterDir;
    final items = <DoctorCheckItem>[];

    final pubspec = File(join(flutterDir.path, 'pubspec.yaml'));
    items.add(
      fileOrDirPresent(
        id: 'flutter_pubspec',
        title: 'pubspec.yaml',
        exists: pubspec.existsSync(),
        path: pubspec.path,
        fix: '确认 metaapp_flutter 工程完整',
        group: group,
      ),
    );

    final fvmConfigDir = findFvmConfigDir(
      flutterDir,
      stopAt: Directory(appHomeDir.workspace),
    );
    final fvmVersion = fvmConfigDir == null
        ? null
        : readConfiguredFvmVersion(fvmConfigDir);
    if (fvmVersion != null && fvmVersion.isNotEmpty) {
      final loc = fvmConfigDir!.path == flutterDir.path
          ? 'metaapp_flutter'
          : fvmConfigDir.path;
      items.add(
        DoctorCheckItem(
          id: 'flutter_fvmrc',
          title: 'FVM Flutter 版本',
          ok: true,
          severity: DoctorCheckSeverity.info,
          detail: '$fvmVersion（$loc）',
          group: group,
        ),
      );
    } else {
      items.add(
        DoctorCheckItem(
          id: 'flutter_fvmrc',
          title: 'FVM Flutter 版本',
          ok: false,
          severity: DoctorCheckSeverity.error,
          detail:
              '从 ${flutterDir.path} 向上未找到 .fvmrc / .fvm/fvm_config.json'
              '（含 melos 仓库根 ${appHomeDir.workspace}）',
          fix: '在 melos 最外层仓库根执行 fvm use x.y.z 并提交 .fvmrc'
              '（不必放在 metaapp_flutter 内）',
          group: group,
        ),
      );
    }

    final fvmPath = await whichCommand('fvm', environment: environment);
    if (fvmPath != null && flutterDir.existsSync()) {
      final fvmCwd = fvmConfigDir ?? flutterDir;
      try {
        final result = await Process.run(
          'fvm',
          ['flutter', '--version'],
          workingDirectory: fvmCwd.path,
          environment: environment,
          runInShell: false,
        ).timeout(const Duration(seconds: 25));
        if (result.exitCode == 0) {
          final line = result.stdout
              .toString()
              .trim()
              .split('\n')
              .firstWhere((l) => l.trim().isNotEmpty, orElse: () => 'ok');
          items.add(
            DoctorCheckItem(
              id: 'flutter_sdk',
              title: 'fvm flutter',
              ok: true,
              severity: DoctorCheckSeverity.info,
              detail: line,
              group: group,
            ),
          );
        } else {
          items.add(
            DoctorCheckItem(
              id: 'flutter_sdk',
              title: 'fvm flutter',
              ok: false,
              severity: DoctorCheckSeverity.error,
              detail: 'exit ${result.exitCode}: ${result.stderr}'.trim(),
              fix: '在 metaapp_flutter 执行 fvm install / fvm use',
              group: group,
            ),
          );
        }
      } catch (e) {
        items.add(
          DoctorCheckItem(
            id: 'flutter_sdk',
            title: 'fvm flutter',
            ok: false,
            severity: DoctorCheckSeverity.error,
            detail: '$e',
            fix: '在 metaapp_flutter 执行 fvm install / fvm use',
            group: group,
          ),
        );
      }
    }

    final melos = File(join(appHomeDir.workspace, 'melos.yaml'));
    if (melos.existsSync()) {
      items.add(
        DoctorCheckItem(
          id: 'melos_yaml',
          title: 'melos.yaml',
          ok: true,
          severity: DoctorCheckSeverity.info,
          detail: melos.path,
          group: group,
        ),
      );
    }

    return items;
  }

  Future<List<DoctorCheckItem>> _checkIos() async {
    const group = 'ios';
    final items = <DoctorCheckItem>[];
    items.add(
      fileOrDirPresent(
        id: 'ios_dir',
        title: '目录 ios/',
        exists: appHomeDir.iosDir.existsSync(),
        path: appHomeDir.iosDir.path,
        fix: '确认 iOS 宿主工程存在',
        group: group,
      ),
    );

    for (final c in [
      (
        id: 'cmd_pod',
        name: 'pod',
        fix: '安装 CocoaPods：sudo gem install cocoapods / brew install cocoapods',
      ),
      (
        id: 'cmd_xcodebuild',
        name: 'xcodebuild',
        fix: '安装 Xcode Command Line Tools / 完整 Xcode',
      ),
      (
        id: 'cmd_fastlane_ios',
        name: 'fastlane',
        fix: '安装 fastlane（IPA 上传 TestFlight 需要）',
      ),
    ]) {
      final path = await whichCommand(c.name, environment: environment);
      items.add(
        commandPresent(
          id: c.id,
          title: '命令 ${c.name}',
          path: path,
          fix: c.fix,
          missingSeverity: c.name == 'fastlane'
              ? DoctorCheckSeverity.warning
              : DoctorCheckSeverity.error,
          group: group,
        ),
      );
    }

    final podfile = File(join(appHomeDir.iosDir.path, 'Podfile'));
    items.add(
      fileOrDirPresent(
        id: 'ios_podfile',
        title: 'ios/Podfile',
        exists: podfile.existsSync(),
        path: podfile.path,
        fix: '确认 iOS 工程完整',
        missingSeverity: DoctorCheckSeverity.warning,
        group: group,
      ),
    );

    return items;
  }

  Future<List<DoctorCheckItem>> _checkAndroid() async {
    const group = 'android';
    final items = <DoctorCheckItem>[];
    items.add(
      fileOrDirPresent(
        id: 'android_dir',
        title: '目录 android/',
        exists: appHomeDir.androidDir.existsSync(),
        path: appHomeDir.androidDir.path,
        fix: '确认 Android 宿主工程存在',
        group: group,
      ),
    );

    final gradlew = File(join(appHomeDir.androidDir.path, 'gradlew'));
    items.add(
      fileOrDirPresent(
        id: 'android_gradlew',
        title: 'android/gradlew',
        exists: gradlew.existsSync(),
        path: gradlew.path,
        fix: '确认 Android 工程含 Gradle Wrapper',
        group: group,
      ),
    );

    final localProps = File(
      join(appHomeDir.androidDir.path, 'local.properties'),
    );
    if (!localProps.existsSync()) {
      items.add(
        DoctorCheckItem(
          id: 'android_local_properties',
          title: 'android/local.properties',
          ok: false,
          severity: DoctorCheckSeverity.error,
          detail: '不存在: ${localProps.path}',
          fix: 'metax init project / app_environment 写入 sdk.dir、ndk.dir',
          group: group,
        ),
      );
    } else {
      final props = readLocalPropertiesFile(localProps);
      final sdkDir = (props['sdk.dir'] ?? '').trim();
      final ndkDir = (props['ndk.dir'] ?? '').trim();
      final sdkOk = sdkDir.isNotEmpty && Directory(sdkDir).existsSync();
      items.add(
        DoctorCheckItem(
          id: 'android_sdk_dir',
          title: 'local.properties sdk.dir',
          ok: sdkOk,
          severity: sdkOk
              ? DoctorCheckSeverity.info
              : DoctorCheckSeverity.error,
          detail: sdkDir.isEmpty
              ? '未配置 sdk.dir'
              : (Directory(sdkDir).existsSync()
                  ? sdkDir
                  : '路径不存在: $sdkDir'),
          fix: '在 local.properties 配置有效 Android SDK，或 metax init app_environment',
          group: group,
        ),
      );
      final ndkStatus = validateAndroidNdkDir(ndkDir);
      items.add(
        DoctorCheckItem(
          id: 'android_ndk_dir',
          title: 'local.properties ndk.dir',
          ok: ndkStatus.ok,
          severity: ndkStatus.ok
              ? DoctorCheckSeverity.info
              : DoctorCheckSeverity.error,
          detail: ndkStatus.detail,
          fix: ndkStatus.fix,
          group: group,
        ),
      );
    }

    final javaPath = await whichCommand('java', environment: environment);
    items.add(
      commandPresent(
        id: 'cmd_java',
        title: '命令 java',
        path: javaPath,
        fix: '安装 JDK（Gradle 构建需要）',
        missingSeverity: DoctorCheckSeverity.warning,
        group: group,
      ),
    );

    final fastlane = await whichCommand('fastlane', environment: environment);
    items.add(
      commandPresent(
        id: 'cmd_fastlane_android',
        title: '命令 fastlane',
        path: fastlane,
        fix: '安装 fastlane（APK 上传 Zealot 等需要）',
        missingSeverity: DoctorCheckSeverity.warning,
        group: group,
      ),
    );

    return items;
  }

  Future<List<DoctorCheckItem>> _checkOhos() async {
    const group = 'ohos';
    final items = <DoctorCheckItem>[];
    items.add(
      fileOrDirPresent(
        id: 'ohos_dir',
        title: '目录 ohos/',
        exists: appHomeDir.ohosDir.existsSync(),
        path: appHomeDir.ohosDir.path,
        fix: '确认鸿蒙宿主工程存在',
        group: group,
      ),
    );

    for (final c in [
      (
        id: 'cmd_ohpm',
        name: 'ohpm',
        fix: '安装 DevEco / 配置 ohpm 到 PATH（Unity HAR 需要）',
        sev: DoctorCheckSeverity.warning,
      ),
      (
        id: 'cmd_hvigorw',
        name: 'hvigorw',
        fix: '将 hvigorw 加入 PATH，或安装 OpenHarmony SDK',
        sev: DoctorCheckSeverity.warning,
      ),
      (
        id: 'cmd_fastlane_ohos',
        name: 'fastlane',
        fix: '安装 fastlane（hap/ohos 构建与上传需要）',
        sev: DoctorCheckSeverity.error,
      ),
    ]) {
      final path = await whichCommand(c.name, environment: environment);
      items.add(
        commandPresent(
          id: c.id,
          title: '命令 ${c.name}',
          path: path,
          fix: c.fix,
          missingSeverity: c.sev,
          group: group,
        ),
      );
    }

    final localProps = File(join(appHomeDir.ohosDir.path, 'local.properties'));
    items.add(
      fileOrDirPresent(
        id: 'ohos_local_properties',
        title: 'ohos/local.properties',
        exists: localProps.existsSync(),
        path: localProps.path,
        fix: '确认鸿蒙工程已配置 SDK',
        missingSeverity: DoctorCheckSeverity.warning,
        group: group,
      ),
    );

    return items;
  }

  Future<List<DoctorCheckItem>> _checkUnity(Map<String, String>? appEnv) async {
    const group = 'unity';
    final env = {...?appEnv, ...environment};
    final items = <DoctorCheckItem>[];

    for (final c in [
      (
        id: 'cmd_build_winner_app',
        name: 'build_winner_app',
        fix: '安装并配置 build_winner_app 到 PATH（Unity 缓存导出硬依赖）',
        sev: DoctorCheckSeverity.error,
      ),
      (
        id: 'cmd_cmake',
        name: 'cmake',
        fix: '安装 cmake（Unity 缓存导出硬依赖）',
        sev: DoctorCheckSeverity.error,
      ),
    ]) {
      final path = await whichCommand(c.name, environment: environment);
      items.add(
        commandPresent(
          id: c.id,
          title: '命令 ${c.name}',
          path: path,
          fix: c.fix,
          missingSeverity: c.sev,
          group: group,
        ),
      );
    }

    items.add(
      envKeysPresent(
        id: 'unity_env_paths',
        title: 'Unity 路径环境变量',
        env: env,
        keys: const [
          'UNITY_WORKSPACE',
          'IOS_UNITY_PATH',
          'ANDROID_UNITY_PATH',
          'UNITY_ENGINE_PATH',
        ],
        fix: 'metax init app_environment 写入 UNITY_* 变量',
        group: group,
      ),
    );

    final engine = (env['UNITY_ENGINE_PATH'] ?? '').trim();
    if (engine.isNotEmpty) {
      items.add(
        fileOrDirPresent(
          id: 'unity_engine_bin',
          title: 'UNITY_ENGINE_PATH',
          exists: File(engine).existsSync() || Directory(engine).existsSync(),
          path: engine,
          fix: '修正 UNITY_ENGINE_PATH 指向有效 Unity 引擎',
          group: group,
        ),
      );
    }

    final tuanjie = (env['TUANJIE_ENGINE_PATH'] ?? '').trim();
    if (tuanjie.isNotEmpty) {
      items.add(
        fileOrDirPresent(
          id: 'tuanjie_engine_bin',
          title: 'TUANJIE_ENGINE_PATH',
          exists: File(tuanjie).existsSync() || Directory(tuanjie).existsSync(),
          path: tuanjie,
          fix: '修正 TUANJIE_ENGINE_PATH（鸿蒙 Unity/团结）',
          group: group,
        ),
      );
    } else if (_resolvePlatforms().contains('ohos')) {
      items.add(
        const DoctorCheckItem(
          id: 'tuanjie_engine_bin',
          title: 'TUANJIE_ENGINE_PATH',
          ok: false,
          severity: DoctorCheckSeverity.warning,
          detail: '未设置（鸿蒙 Unity HAR 需要）',
          fix: 'metax init app_environment 配置 TUANJIE_ENGINE_PATH / OHOS_UNITY_PATH',
          group: group,
        ),
      );
    }

    return items;
  }

  List<DoctorCheckItem> _checkAppwriteKeys(Map<String, String>? appEnv) {
    const group = 'appwrite';
    if (appEnv == null) {
      return [
        const DoctorCheckItem(
          id: 'appwrite_env',
          title: 'Appwrite 环境',
          ok: false,
          severity: DoctorCheckSeverity.error,
          detail: '无法加载 jenkins_ci/env（app + appwrite）',
          fix: 'metax init app_environment',
          group: group,
        ),
      ];
    }
    return [
      envKeysPresent(
        id: 'appwrite_core',
        title: 'Appwrite 基础凭据',
        env: appEnv,
        keys: const [
          'APPWRITE_ENDPOINT',
          'APPWRITE_PROJECT_ID',
          'APPWRITE_API_KEY',
        ],
        fix: '补全 jenkins_ci/env/appwrite/.env',
        group: group,
      ),
      envKeysPresent(
        id: 'appwrite_zip',
        title: 'Appwrite Zip 缓存集合',
        env: appEnv,
        keys: const [
          'APPWRITE_ZIP_DATABASE_ID',
          'APPWRITE_ZIP_COLLECTION_ID',
          'APPWRITE_ZIP_BUCKET_ID',
        ],
        fix: '补全 APPWRITE_ZIP_*（cache upload/download）',
        missingSeverity: DoctorCheckSeverity.warning,
        group: group,
      ),
      envKeysPresent(
        id: 'appwrite_build',
        title: 'Appwrite 构建记录集合',
        env: appEnv,
        keys: const [
          'APPWRITE_BUILD_DATABASE_ID',
          'APPWRITE_BUILD_COLLECTION_ID',
          'APPWRITE_BUILD_BRANCH_COLLECTION_ID',
        ],
        fix: '补全 APPWRITE_BUILD_*（upload 记录 / patch 预审）',
        missingSeverity: DoctorCheckSeverity.warning,
        group: group,
      ),
    ];
  }

  List<DoctorCheckItem> _checkUploadSecrets() {
    const group = 'upload';
    Map<String, String> env;
    try {
      env = loadBuildAppEnvironment(appHomeDir, false);
    } catch (e) {
      return [
        DoctorCheckItem(
          id: 'upload_env',
          title: 'build_app 环境',
          ok: false,
          severity: DoctorCheckSeverity.error,
          detail: '$e',
          fix: 'metax init app_environment，并检查 jenkins_ci/env/build_app/',
          group: group,
        ),
      ];
    }

    return [
      envKeysPresent(
        id: 'upload_hooks',
        title: '企业微信 Hook',
        env: env,
        keys: const ['IOS_HOOK_URL', 'ANDROID_HOOK_URL'],
        fix: '补全 jenkins_ci/env/build_app 中的 *_HOOK_URL',
        missingSeverity: DoctorCheckSeverity.warning,
        group: group,
      ),
      envKeysPresent(
        id: 'upload_zealot',
        title: 'Zealot',
        env: env,
        keys: const [
          'ZEALOT_ENDPOINT',
          'ZEALOT_TOKEN',
          'ZEALOT_CHANNEL_KEY',
        ],
        fix: '补全 ZEALOT_*',
        missingSeverity: DoctorCheckSeverity.warning,
        group: group,
      ),
      envKeysPresent(
        id: 'upload_sentry',
        title: 'Sentry',
        env: env,
        keys: const [
          'SENTRY_URL',
          'SENTRY_AUTH_TOKEN',
          'SENTRY_ORG',
          'SENTRY_PROJECT',
        ],
        fix: '补全 SENTRY_*；并确保 PATH 有 sentry-cli',
        missingSeverity: DoctorCheckSeverity.warning,
        group: group,
      ),
      envKeysPresent(
        id: 'upload_asc',
        title: 'App Store Connect',
        env: env,
        keys: const [
          'APP_STORE_CONNECT_API_KEY_FILEPATH',
          'APP_STORE_CONNECT_API_KEY_ID',
          'APP_STORE_CONNECT_API_KEY_ISSUER_ID',
          'APP_IDENTIFIER',
        ],
        fix: '补全 ASC API Key 相关变量（iOS 上传）',
        missingSeverity: DoctorCheckSeverity.warning,
        group: group,
      ),
    ];
  }
}
