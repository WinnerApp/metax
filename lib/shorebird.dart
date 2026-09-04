import 'dart:io';

import 'package:meta_tool/app_home_dir.dart';
import 'package:meta_tool/common.dart';
import 'package:meta_tool/estimated_progress.dart';
import 'package:meta_tool/flutter_sdk.dart';
import 'package:path/path.dart';
import 'package:process_runner/process_runner.dart';
import 'package:yaml/yaml.dart';

/// Shorebird / metax 启用解析结果
class ShorebirdResolveResult {
  final bool enabled;
  final String reason;
  final ShorebirdYamlConfig? yaml;

  const ShorebirdResolveResult({
    required this.enabled,
    required this.reason,
    this.yaml,
  });
}

/// `metaapp_flutter/shorebird.yaml` 解析结果（仅 Shorebird 官方字段）。
///
/// **不要**往 shorebird.yaml 写 `metax_enabled`：Shorebird CLI 会校验 key 并报错。
class ShorebirdYamlConfig {
  final String? appId;
  final String? baseUrl;
  final File file;

  const ShorebirdYamlConfig({
    required this.file,
    this.appId,
    this.baseUrl,
  });

  static File yamlFile(Directory flutterDir) =>
      File(join(flutterDir.path, 'shorebird.yaml'));

  static ShorebirdYamlConfig? tryLoad(Directory flutterDir) {
    final file = yamlFile(flutterDir);
    if (!file.existsSync()) {
      return null;
    }
    try {
      final doc = loadYaml(file.readAsStringSync());
      if (doc is! YamlMap) {
        return ShorebirdYamlConfig(file: file);
      }
      return ShorebirdYamlConfig(
        file: file,
        appId: doc['app_id']?.toString(),
        baseUrl: doc['base_url']?.toString(),
      );
    } catch (e) {
      loggerWarning('解析 shorebird.yaml 失败: $e');
      return ShorebirdYamlConfig(file: file);
    }
  }
}

/// 从 `metaapp_flutter/pubspec.yaml` 读取 metax Shorebird 开关。
///
/// 推荐写法：
/// ```yaml
/// metax:
///   shorebird_enabled: true
/// ```
bool? readMetaxShorebirdEnabled(Directory flutterDir) {
  final file = File(join(flutterDir.path, 'pubspec.yaml'));
  if (!file.existsSync()) {
    return null;
  }
  try {
    final doc = loadYaml(file.readAsStringSync());
    if (doc is! YamlMap) {
      return null;
    }
    final metax = doc['metax'];
    if (metax is YamlMap) {
      if (metax.containsKey('shorebird_enabled')) {
        return _asBool(metax['shorebird_enabled']);
      }
      if (metax.containsKey('shorebird')) {
        return _asBool(metax['shorebird']);
      }
    }
    // 兼容顶层（pub 会忽略未知 key）
    if (doc.containsKey('metax_enabled')) {
      return _asBool(doc['metax_enabled']);
    }
  } catch (e) {
    loggerWarning('解析 pubspec.yaml metax 开关失败: $e');
  }
  return null;
}

bool? _asBool(dynamic value) {
  if (value is bool) return value;
  if (value == null) return null;
  final text = value.toString().trim().toLowerCase();
  if (text == 'true' || text == '1' || text == 'yes') return true;
  if (text == 'false' || text == '0' || text == 'no') return false;
  return null;
}

/// 解析是否启用 Shorebird。
///
/// 优先级：CLI 显式 > `SHOREBIRD_ENABLED` > `pubspec.yaml` 的 `metax.shorebird_enabled` > 默认 false。
/// **禁止**仅凭 `shorebird.yaml` 文件是否存在来判断；也**不要**往 shorebird.yaml 写自定义 key。
ShorebirdResolveResult resolveUseShorebird({
  required AppHomeDir appHomeDir,
  bool? explicitUseShorebird,
  Map<String, String>? environment,
}) {
  final env = environment ?? Platform.environment;
  final yaml = ShorebirdYamlConfig.tryLoad(appHomeDir.flutterDir);
  final pubspecEnabled = readMetaxShorebirdEnabled(appHomeDir.flutterDir);

  if (explicitUseShorebird == false) {
    return ShorebirdResolveResult(
      enabled: false,
      reason: 'CLI --no-useShorebird',
      yaml: yaml,
    );
  }
  if (explicitUseShorebird == true) {
    return ShorebirdResolveResult(
      enabled: true,
      reason: 'CLI --useShorebird',
      yaml: yaml,
    );
  }

  final envRaw = (env['SHOREBIRD_ENABLED'] ?? '').trim().toLowerCase();
  if (envRaw == 'true' || envRaw == '1' || envRaw == 'yes') {
    return ShorebirdResolveResult(
      enabled: true,
      reason: 'SHOREBIRD_ENABLED=true',
      yaml: yaml,
    );
  }
  if (envRaw == 'false' || envRaw == '0' || envRaw == 'no') {
    return ShorebirdResolveResult(
      enabled: false,
      reason: 'SHOREBIRD_ENABLED=false',
      yaml: yaml,
    );
  }

  if (pubspecEnabled == true) {
    return ShorebirdResolveResult(
      enabled: true,
      reason: 'pubspec.yaml metax.shorebird_enabled=true',
      yaml: yaml,
    );
  }
  if (pubspecEnabled == false) {
    return ShorebirdResolveResult(
      enabled: false,
      reason: 'pubspec.yaml metax.shorebird_enabled=false',
      yaml: yaml,
    );
  }

  return ShorebirdResolveResult(
    enabled: false,
    reason: 'pubspec.yaml metax.shorebird_enabled unset / default off',
    yaml: yaml,
  );
}

String buildShorebirdReleaseVersion({
  required String buildName,
  required String buildNumber,
}) {
  final name = buildName.trim();
  final number = buildNumber.trim();
  if (name.isEmpty || number.isEmpty) {
    throw ArgumentError('buildName/buildNumber 不能为空');
  }
  if (name.contains('+')) {
    return name;
  }
  return '$name+$number';
}

/// 解析 `1.2.3+456` → (buildName, buildNumber)。
({String buildName, String buildNumber}) parseShorebirdReleaseVersion(
  String releaseVersion,
) {
  final raw = releaseVersion.trim();
  final plus = raw.lastIndexOf('+');
  if (plus <= 0 || plus >= raw.length - 1) {
    throw ArgumentError(
      'release-version 格式应为 buildName+buildNumber，例如 1.2.3+456，收到: $releaseVersion',
    );
  }
  final buildName = raw.substring(0, plus).trim();
  final buildNumber = raw.substring(plus + 1).trim();
  if (buildName.isEmpty || buildNumber.isEmpty) {
    throw ArgumentError(
      'release-version 格式应为 buildName+buildNumber，例如 1.2.3+456，收到: $releaseVersion',
    );
  }
  return (buildName: buildName, buildNumber: buildNumber);
}

String? resolveReleaseVersionFromEnv([Map<String, String>? environment]) {
  final env = environment ?? Platform.environment;
  final explicit = (env['SHOREBIRD_RELEASE_VERSION'] ?? '').trim();
  if (explicit.isNotEmpty) return explicit;
  final name = (env['BUILD_VERSION_NAME'] ?? env['BUILD_NAME'] ?? '').trim();
  final number =
      (env['BUILD_VERSION_NUMBER'] ?? env['BUILD_NUMBER'] ?? '').trim();
  if (name.isNotEmpty && number.isNotEmpty) {
    return buildShorebirdReleaseVersion(buildName: name, buildNumber: number);
  }
  return null;
}

String shorebirdFlutterSdkFingerprint(String baseFingerprint) {
  if (baseFingerprint.endsWith('@shorebird')) return baseFingerprint;
  return '$baseFingerprint@shorebird';
}

bool isShorebirdFlutterSdkFingerprint(String fingerprint) {
  return fingerprint.contains('@shorebird');
}

/// 判断缓存条目是否为 Shorebird 产物。
///
/// 优先看显式字段 [CacheModel.isShorebird]；旧缓存无该字段时回退到
/// `flutterSdk` 指纹中的 `@shorebird` 标记。
bool cacheEntryIsShorebird({
  required bool isShorebird,
  required String flutterSdk,
}) {
  if (isShorebird) return true;
  return isShorebirdFlutterSdkFingerprint(flutterSdk);
}

Future<void> ensureShorebirdInstalled() async {
  try {
    final result = await ProcessRunner().runProcess(
      ['which', 'shorebird'],
      printOutput: false,
    );
    if (result.stdout.trim().isEmpty) {
      throw Exception('shorebird not found');
    }
  } catch (_) {
    throw Exception(
      '未找到 shorebird CLI。请安装: '
      'curl --proto "=https" --tlsv1.2 https://raw.githubusercontent.com/shorebirdtech/install/main/install.sh -sSf | bash',
    );
  }
}

/// 解析传给 `--flutter-version` 的版本号（优先 FVM 配置）
String resolveShorebirdFlutterVersion({
  required Directory flutterDir,
  FlutterSdkInfo? sdk,
}) {
  final configured = readConfiguredFvmVersion(flutterDir);
  if (configured != null && configured.isNotEmpty) {
    // FVM 可能是 custom 名；尽量取纯版本号段
    final match = RegExp(r'(\d+\.\d+\.\d+)').firstMatch(configured);
    if (match != null) return match.group(1)!;
    return configured;
  }
  if (sdk != null) {
    final match = RegExp(r'^([^@]+)').firstMatch(sdk.fingerprint);
    if (match != null && match.group(1)!.isNotEmpty) {
      return match.group(1)!;
    }
  }
  throw Exception(
    '无法解析 Shorebird --flutter-version，请在 metaapp_flutter/.fvmrc 配置 Flutter 版本',
  );
}

/// Shorebird CLI 构建/登记用的官方 API。
///
/// 与 `shorebird.yaml` 的 `base_url`（设备 OTA / Meta Code Push）无关。
/// 故意覆盖环境里的 `SHOREBIRD_HOSTED_URL`，避免误把 OTA 地址当成 Console API。
const kShorebirdOfficialHostedUrl = 'https://api.shorebird.dev';

/// Shorebird 打包用的 Flutter 引擎/制品下载源（覆盖国内镜像等误配）。
const kShorebirdFlutterStorageBaseUrl = 'https://download.shorebird.dev';

Map<String, String> shorebirdCliEnvironment([Map<String, String>? base]) {
  final env = Map<String, String>.from(base ?? Platform.environment);
  env['SHOREBIRD_HOSTED_URL'] = kShorebirdOfficialHostedUrl;
  env['FLUTTER_STORAGE_BASE_URL'] = kShorebirdFlutterStorageBaseUrl;
  return env;
}

/// Shorebird 自身选项之后，用 `--` 把参数代理给 flutter。
///
/// 不要传 `--packages=` / `--no-pub`：Shorebird 使用自带 Flutter，会重写
/// `.dart_tool`；`--no-pub` 会阻止其重新 `pub get`，导致
/// `package_config.json does not exist` / monorepo `package_graph` 解析失败。
///
/// 不要在透传参数里传 `--target-platform`：Shorebird 会按自身
/// `--target-platform`（默认三 ABI）再拼进 `flutter build aar`；若透传再带
/// 一次，MultiOption 会合并出重复 ABI，触发
/// `packJniLibsflutterBuildRelease` 的 `libapp.so is a duplicate`。
/// ABI 限制请放进 [extraShorebirdArgs]。
///
/// release / patch 都强制 `--no-tree-shake-icons`，避免 MaterialIcons /
/// tdesign 等图标字体因树摇子集不一致触发 asset diff。
List<String> _shorebirdFlutterPassthroughArgs(List<String> flutterArgs) {
  final args = List<String>.of(flutterArgs).where((arg) {
    return !arg.startsWith('--target-platform');
  }).toList();
  if (!args.contains('--no-tree-shake-icons')) {
    args.add('--no-tree-shake-icons');
  }
  return <String>[
    '--',
    ...args,
  ];
}

Future<void> runShorebirdRelease({
  required Directory flutterDir,
  required String platform, // ios-framework | aar
  required String releaseVersion,
  required String flutterVersion,
  List<String> extraFlutterArgs = const [],
  /// Shorebird CLI 自身参数（写在 `--` 前），例如 `--target-platform=android-arm64`。
  List<String> extraShorebirdArgs = const [],
}) async {
  await ensureShorebirdInstalled();
  final yaml = ShorebirdYamlConfig.tryLoad(flutterDir);
  if (yaml?.appId == null || yaml!.appId!.trim().isEmpty) {
    throw Exception(
      '已启用 Shorebird，但 ${ShorebirdYamlConfig.yamlFile(flutterDir).path} 缺少 app_id',
    );
  }

  // iOS / Android 共用 flutter/release；不清空会把上一平台残留打进下一平台缓存。
  await clearShorebirdReleaseDir(flutterDir);

  final args = <String>[
    'release',
    platform,
    '--release-version',
    releaseVersion,
    '--flutter-version',
    flutterVersion,
    ...extraShorebirdArgs,
    ..._shorebirdFlutterPassthroughArgs(extraFlutterArgs),
  ];

  final cliEnv = shorebirdCliEnvironment();
  loggerInfo(
    '执行: shorebird ${args.join(' ')} '
    '(SHOREBIRD_HOSTED_URL=${cliEnv['SHOREBIRD_HOSTED_URL']}, '
    'FLUTTER_STORAGE_BASE_URL=${cliEnv['FLUTTER_STORAGE_BASE_URL']})',
  );

  final sw = Stopwatch()..start();
  try {
    await ProcessRunner(environment: cliEnv).runProcess(
      ['shorebird', ...args],
      workingDirectory: flutterDir,
      printOutput: true,
    );
    loggerInfo(
      'shell 完成: shorebird ${args.take(2).join(' ')} · '
      '用时 ${formatElapsedDuration(sw.elapsed)}',
    );
  } catch (e) {
    loggerInfo(
      'shell 失败: shorebird ${args.take(2).join(' ')} · '
      '用时 ${formatElapsedDuration(sw.elapsed)}',
    );
    rethrow;
  }
}

/// 清理 Shorebird 共用的 `flutter/release`，避免跨平台产物混入。
Future<void> clearShorebirdReleaseDir(Directory flutterDir) async {
  final releaseDir = Directory(join(flutterDir.path, 'release'));
  if (!await releaseDir.exists()) {
    return;
  }
  await releaseDir.delete(recursive: true);
  loggerInfo('已清理旧 Shorebird release 目录: ${releaseDir.path}');
}

/// 从目录顶层移除 iOS framework 残留（xcframework / podspec / Privacys）。
Future<int> stripIosArtifactsFromCacheDir(Directory dir) async {
  if (!await dir.exists()) {
    return 0;
  }
  var removed = 0;
  await for (final entity in dir.list(followLinks: false)) {
    final name = basename(entity.path);
    final shouldRemove = (entity is Directory &&
            (name.endsWith('.xcframework') || name == 'Privacys')) ||
        (entity is File &&
            (name.endsWith('.podspec') ||
                name == 'Podfile' ||
                name == 'Podfile.lock'));
    if (!shouldRemove) {
      continue;
    }
    await entity.delete(recursive: true);
    removed++;
  }
  if (removed > 0) {
    loggerWarning(
      '已从 ${dir.path} 剥离 $removed 个 iOS 残留产物（避免污染 Android 缓存）',
    );
  }
  return removed;
}

/// 从目录顶层移除 Android AAR/Maven 残留。
Future<int> stripAndroidArtifactsFromCacheDir(Directory dir) async {
  if (!await dir.exists()) {
    return 0;
  }
  var removed = 0;
  await for (final entity in dir.list(followLinks: false)) {
    final name = basename(entity.path);
    final shouldRemove = (entity is Directory && name == 'android_generated') ||
        (entity is File && name.endsWith('.aar'));
    if (!shouldRemove) {
      continue;
    }
    await entity.delete(recursive: true);
    removed++;
  }
  if (removed > 0) {
    loggerWarning(
      '已从 ${dir.path} 剥离 $removed 个 Android 残留产物（避免污染 iOS 缓存）',
    );
  }
  return removed;
}

Future<void> runShorebirdPatch({
  required Directory flutterDir,
  required String platform, // ios-framework | aar
  required String releaseVersion,
  bool allowAssetDiffs = false,
}) async {
  await ensureShorebirdInstalled();
  final args = <String>[
    'patch',
    platform,
    '--release-version',
    releaseVersion,
    if (allowAssetDiffs) '--allow-asset-diffs',
    ..._shorebirdFlutterPassthroughArgs(const []),
  ];
  loggerInfo('执行: shorebird ${args.join(' ')}');
  final sw = Stopwatch()..start();
  try {
    await ProcessRunner(environment: shorebirdCliEnvironment()).runProcess(
      ['shorebird', ...args],
      workingDirectory: flutterDir,
      printOutput: true,
    );
    loggerInfo(
      'shell 完成: shorebird ${args.take(2).join(' ')} · '
      '用时 ${formatElapsedDuration(sw.elapsed)}',
    );
  } catch (e) {
    loggerInfo(
      'shell 失败: shorebird ${args.take(2).join(' ')} · '
      '用时 ${formatElapsedDuration(sw.elapsed)}',
    );
    rethrow;
  }
}

/// 将 Shorebird iOS release 产物同步到 metax 习惯的 framework 缓存目录
Future<void> syncShorebirdIosReleaseToFrameworkDir(Directory flutterDir) async {
  final releaseDir = Directory(join(flutterDir.path, 'release'));
  final targetDir =
      Directory(join(flutterDir.path, 'build', 'ios', 'framework', 'Release'));

  if (releaseDir.existsSync()) {
    if (targetDir.existsSync()) {
      await targetDir.delete(recursive: true);
    }
    await targetDir.create(recursive: true);
    await copyDirToDir(releaseDir, targetDir);
    loggerInfo('已从 Shorebird release 同步产物到 ${targetDir.path}');
  } else if (targetDir.existsSync()) {
    // shorebird release 上传失败时，可能只留下 build 目录产物
    loggerWarning(
      '未找到 ${releaseDir.path}，改用已有产物目录: ${targetDir.path}',
    );
  } else {
    throw Exception(
      'Shorebird iOS 产物不存在（需要 ${releaseDir.path} 或 ${targetDir.path}）',
    );
  }

  await stripAndroidArtifactsFromCacheDir(targetDir);

  // Shorebird 产出 ShorebirdFlutter.xcframework（内含 Flutter.framework）。
  // CocoaPods 按 xcframework 文件名链接，必须改回 Flutter.xcframework，否则会报
  // framework 'ShorebirdFlutter' not found。
  final flutterXc = Directory(join(targetDir.path, 'Flutter.xcframework'));
  final shorebirdXc =
      Directory(join(targetDir.path, 'ShorebirdFlutter.xcframework'));
  if (shorebirdXc.existsSync()) {
    if (flutterXc.existsSync()) {
      await flutterXc.delete(recursive: true);
    }
    await shorebirdXc.rename(flutterXc.path);
    loggerInfo(
      '已将 ShorebirdFlutter.xcframework 重命名为 Flutter.xcframework（CocoaPods 链接）',
    );
  }
  if (flutterXc.existsSync()) {
    final flutterPodspec = File(join(targetDir.path, 'Flutter.podspec'));
    await flutterPodspec.writeAsString('''
#
# Shorebird 引擎对外仍暴露为 Flutter pod。
# 必须使用 Flutter.xcframework 文件名，否则 CocoaPods 会错误链接 ShorebirdFlutter。
#

Pod::Spec.new do |s|
  s.name                  = 'Flutter'
  s.version               = '1.0.0'
  s.summary               = 'Flutter engine (Shorebird)'
  s.description           = 'Shorebird engine exposed as Flutter for CocoaPods'
  s.homepage              = 'https://flutter.dev'
  s.license               = { :type => 'BSD' }
  s.author                = { 'Flutter Dev Team' => 'flutter-dev@googlegroups.com' }
  s.source                = { :path => '.' }
  s.platform              = :ios, '13.0'
  s.vendored_frameworks   = 'Flutter.xcframework'
end
''');
    loggerInfo('已写入 Flutter.podspec（vendored Flutter.xcframework / Shorebird）');
    final staleShorebirdPodspec =
        File(join(targetDir.path, 'ShorebirdFlutter.podspec'));
    if (staleShorebirdPodspec.existsSync()) {
      await staleShorebirdPodspec.delete();
      loggerInfo('已删除错误的 ShorebirdFlutter.podspec');
    }
  } else {
    throw Exception(
      'Shorebird sync 后未找到 Flutter.xcframework: ${flutterXc.path}',
    );
  }

  loggerInfo('已完成 Shorebird iOS 产物同步: ${targetDir.path}');
}

/// Shorebird / flutter build aar 的 Maven 仓库相对路径（相对 build/host）。
///
/// Android `settings.gradle` 与普通 `flutter build aar` 均约定：
/// `build/host/outputs/repo` → 解压后为 `android/aar/flutter/outputs/repo`。
const kFlutterAarMavenRepoRelativePath = 'outputs/repo';

/// Shorebird `release/` 可能是 Maven 根，也可能已含 `outputs/repo`。
Directory resolveShorebirdAarMavenSource(Directory releaseOrHostDir) {
  final nested = Directory(
    join(releaseOrHostDir.path, kFlutterAarMavenRepoRelativePath),
  );
  if (nested.existsSync()) {
    return nested;
  }
  return releaseOrHostDir;
}

bool _looksLikeMavenRepoRoot(Directory dir) {
  if (!dir.existsSync()) return false;
  // flutter / shorebird AAR 常见顶层：groupId 目录或 android_generated
  for (final name in const ['com', 'io', 'dev', 'android_generated']) {
    if (Directory(join(dir.path, name)).existsSync()) {
      return true;
    }
  }
  return false;
}

/// 将已有 `build/host` 对齐为 `outputs/repo` 布局（兼容旧 Shorebird 扁平产物）。
Future<void> ensureShorebirdHostDirHasOutputsRepo(Directory hostDir) async {
  final outputsRepo = Directory(
    join(hostDir.path, kFlutterAarMavenRepoRelativePath),
  );
  if (outputsRepo.existsSync() && _looksLikeMavenRepoRoot(outputsRepo)) {
    return;
  }
  if (!_looksLikeMavenRepoRoot(hostDir)) {
    // 既没有扁平 Maven，也没有 outputs/repo：保持原样，由后续校验报错
    return;
  }

  final staging = Directory(join(hostDir.path, '.shorebird_repo_staging'));
  if (staging.existsSync()) {
    await staging.delete(recursive: true);
  }
  await staging.create();

  await for (final entity in hostDir.list(followLinks: false)) {
    final name = basename(entity.path);
    // cache.json 留在 host 根，与 flutter build aar 缓存一致
    if (name == '.shorebird_repo_staging' ||
        name == 'cache.json' ||
        name == 'outputs') {
      continue;
    }
    await entity.rename(join(staging.path, name));
  }

  if (outputsRepo.existsSync()) {
    await outputsRepo.delete(recursive: true);
  }
  await outputsRepo.create(recursive: true);
  await for (final entity in staging.list(followLinks: false)) {
    await entity.rename(join(outputsRepo.path, basename(entity.path)));
  }
  await staging.delete(recursive: true);
  loggerInfo('已将 build/host 扁平 Maven 对齐到 ${outputsRepo.path}');
}

/// 将 Shorebird AAR release 产物同步到 flutter build aar 习惯目录
///
/// Shorebird 默认写出 `release/<maven-root>`（无 `outputs/repo`），
/// 而 metax 缓存 / Android 依赖约定为 `build/host/outputs/repo`。
Future<void> syncShorebirdAarReleaseToHostDir(Directory flutterDir) async {
  final releaseDir = Directory(join(flutterDir.path, 'release'));
  final hostDir = Directory(join(flutterDir.path, 'build', 'host'));
  final outputsRepoDir = Directory(
    join(hostDir.path, kFlutterAarMavenRepoRelativePath),
  );

  if (releaseDir.existsSync()) {
    final mavenSource = resolveShorebirdAarMavenSource(releaseDir);
    if (hostDir.existsSync()) {
      await hostDir.delete(recursive: true);
    }
    await outputsRepoDir.create(recursive: true);
    await copyDirToDir(mavenSource, outputsRepoDir);
    // 防御：即使 release 未清空，也不要把 iOS xcframework 打进 android 缓存
    await stripIosArtifactsFromCacheDir(hostDir);
    await stripIosArtifactsFromCacheDir(outputsRepoDir);
    loggerInfo('已同步 Shorebird AAR 产物到 ${outputsRepoDir.path}');
    return;
  }

  // 部分版本可能直接写到 build/host
  if (!hostDir.existsSync()) {
    throw Exception('Shorebird AAR release 目录不存在: ${releaseDir.path}');
  }
  await ensureShorebirdHostDirHasOutputsRepo(hostDir);
  await stripIosArtifactsFromCacheDir(hostDir);
  if (outputsRepoDir.existsSync()) {
    await stripIosArtifactsFromCacheDir(outputsRepoDir);
  }
  loggerInfo(
    '使用已有 build/host 作为 AAR 产物目录（已对齐 $kFlutterAarMavenRepoRelativePath）',
  );
}
