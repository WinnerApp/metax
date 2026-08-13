import 'dart:convert';
import 'dart:io';

import 'package:meta_tool/common.dart';
import 'package:path/path.dart';
import 'package:process_runner/process_runner.dart';

/// 当前 Flutter SDK 解析结果
class FlutterSdkInfo {
  /// 稳定指纹：version@engineRevision，用于判断是否需要清理缓存
  final String fingerprint;

  /// Flutter SDK 根目录
  final String flutterRoot;

  /// 实际执行命令前缀，如 `[fvm, flutter]` 或 `[flutter]`
  final List<String> flutterCommand;

  /// 是否通过 FVM 解析
  final bool usedFvm;

  /// 工程 `.fvmrc` / `fvm_config.json` 中配置的版本名（若有）
  final String? configuredVersion;

  const FlutterSdkInfo({
    required this.fingerprint,
    required this.flutterRoot,
    required this.flutterCommand,
    required this.usedFvm,
    this.configuredVersion,
  });
}

class FlutterSdkGateResult {
  final FlutterSdkInfo sdk;
  final bool didClean;

  const FlutterSdkGateResult({
    required this.sdk,
    required this.didClean,
  });
}

/// 是否存在 FVM 配置
bool hasFvmConfig(Directory projectDir) {
  final fvmrc = File(join(projectDir.path, '.fvmrc'));
  final fvmConfig = File(join(projectDir.path, '.fvm', 'fvm_config.json'));
  return fvmrc.existsSync() || fvmConfig.existsSync();
}

/// 读取工程配置的 FVM Flutter 版本名
String? readConfiguredFvmVersion(Directory projectDir) {
  final fvmrc = File(join(projectDir.path, '.fvmrc'));
  if (fvmrc.existsSync()) {
    final content = fvmrc.readAsStringSync().trim();
    if (content.isEmpty) {
      // fall through
    } else if (content.startsWith('{')) {
      try {
        final json = jsonDecode(content);
        if (json is Map) {
          final version = json['flutter'] ?? json['flutterSdkVersion'];
          if (version != null && version.toString().trim().isNotEmpty) {
            return version.toString().trim();
          }
        }
      } catch (_) {
        // fall through to plain text
      }
    } else {
      return content;
    }
  }

  final fvmConfig = File(join(projectDir.path, '.fvm', 'fvm_config.json'));
  if (fvmConfig.existsSync()) {
    try {
      final json = jsonDecode(fvmConfig.readAsStringSync());
      if (json is Map) {
        final version = json['flutterSdkVersion'] ?? json['flutter'];
        if (version != null && version.toString().trim().isNotEmpty) {
          return version.toString().trim();
        }
      }
    } catch (_) {
      return null;
    }
  }
  return null;
}

Directory fvmVersionsRoot() {
  final home = Platform.environment['HOME'] ?? '';
  final cachePath = Platform.environment['FVM_CACHE_PATH'] ??
      Platform.environment['FVM_HOME'] ??
      join(home, 'fvm');
  return Directory(join(cachePath, 'versions'));
}

Directory fvmVersionDir(String version) {
  return Directory(join(fvmVersionsRoot().path, version));
}

bool isFvmVersionInstalled(String version) {
  final binFlutter = File(join(fvmVersionDir(version).path, 'bin', 'flutter'));
  return binFlutter.existsSync();
}

Future<bool> isFvmAvailable() async {
  try {
    final result = await ProcessRunner().runProcess(
      ['which', 'fvm'],
      printOutput: false,
    );
    return result.stdout.trim().isNotEmpty;
  } catch (_) {
    return false;
  }
}

/// 一律使用 `fvm flutter`（版本由 FVM 按 cwd 向上找 `.fvmrc`）
List<String> resolveFlutterCommand() => const ['fvm', 'flutter'];

/// 确保工程 `.fvmrc` 对应的 Flutter 版本已安装，并完成本地 `fvm use`
///
/// - 官方版本缺失时会尝试 `fvm install`
/// - 鸿蒙/定制 SDK 无法从官方 channel 安装时，给出明确错误提示
Future<String?> ensureFvmFlutterReady(Directory projectDir) async {
  if (!hasFvmConfig(projectDir)) {
    return null;
  }

  final version = readConfiguredFvmVersion(projectDir);
  if (version == null || version.isEmpty) {
    loggerWarning('⚠️ 检测到 FVM 配置文件，但无法解析 Flutter 版本号');
    return null;
  }

  if (!await isFvmAvailable()) {
    throw Exception(
      '工程配置了 FVM 版本 $version，但本机没有 fvm 命令。'
      '请安装: dart pub global activate fvm',
    );
  }

  if (!isFvmVersionInstalled(version)) {
    loggerInfo('📦 FVM 版本未安装: $version，尝试 fvm install ...');
    try {
      await ProcessRunner().runProcess(
        ['fvm', 'install', version],
        workingDirectory: projectDir,
        printOutput: true,
      );
    } catch (e) {
      throw Exception(
        'FVM 版本 $version 未安装，且自动安装失败。\n'
        '期望路径: ${fvmVersionDir(version).path}\n'
        '官方版本可执行: fvm install $version\n'
        '鸿蒙/定制 Flutter 需事先手动安装到 FVM 缓存（无法从官方 channel 拉取），例如:\n'
        '  将 SDK 放到 ${fvmVersionDir(version).path}\n'
        '  或使用 fvm 自定义 git 源安装后再重试\n'
        '原始错误: $e',
      );
    }
    if (!isFvmVersionInstalled(version)) {
      throw Exception(
        'fvm install $version 已执行，但仍未找到 '
        '${join(fvmVersionDir(version).path, 'bin', 'flutter')}',
      );
    }
    loggerSuccess('✅ FVM 版本已安装: $version');
  } else {
    loggerInfo('✅ 已检测到 FVM 版本: $version (${fvmVersionDir(version).path})');
  }

  // 切分支后 .fvm/flutter_sdk 软链可能缺失或指向旧版本，强制对齐到配置版本
  loggerInfo('🔗 对齐工程 FVM 软链: fvm use $version --force');
  try {
    await ProcessRunner().runProcess(
      ['fvm', 'use', version, '--force'],
      workingDirectory: projectDir,
      printOutput: true,
    );
  } catch (e) {
    throw Exception(
      'fvm use $version --force 失败，无法将工程对齐到目标 Flutter 版本: $e',
    );
  }

  return version;
}

/// 解析项目当前应使用的 Flutter SDK（一律 `fvm flutter`）
Future<FlutterSdkInfo> resolveFlutterSdk(Directory projectDir) async {
  final configuredVersion = readConfiguredFvmVersion(projectDir);
  final flutterCommand = resolveFlutterCommand();
  loggerInfo(
    configuredVersion == null
        ? '🔍 使用 fvm flutter'
        : '🔍 检测到 FVM 配置 ($configuredVersion)，使用 fvm flutter',
  );

  final versionMachine = await ProcessRunner().runProcess(
    [...flutterCommand, '--version', '--machine'],
    workingDirectory: projectDir,
    printOutput: true,
  );
  final versionJson = _parseVersionMachineJson(versionMachine.stdout);
  final version = (versionJson['flutterVersion'] ??
          versionJson['frameworkVersion'] ??
          'unknown')
      .toString();
  final engineRevision =
      (versionJson['engineRevision'] ?? versionJson['frameworkRevision'] ?? '')
          .toString();
  final fingerprint =
      engineRevision.isEmpty ? version : '$version@$engineRevision';

  // Prefer flutterRoot from --machine (reliable); which/fvm exec can return a bare
  // "flutter" and File('flutter').parent.parent.path becomes ".".
  var flutterRoot = (versionJson['flutterRoot'] ?? '').toString().trim();
  if (!_isValidFlutterRoot(flutterRoot)) {
    flutterRoot =
        await _resolveFlutterRoot(projectDir, flutterCommand, true);
  }
  if (!_isValidFlutterRoot(flutterRoot) &&
      configuredVersion != null &&
      configuredVersion.isNotEmpty &&
      isFvmVersionInstalled(configuredVersion)) {
    flutterRoot = fvmVersionDir(configuredVersion).path;
  }
  if (!_isValidFlutterRoot(flutterRoot)) {
    throw Exception('无法解析有效的 Flutter SDK 根目录: $flutterRoot');
  }

  loggerInfo('🔍 Flutter SDK: $fingerprint');
  loggerDebug('Flutter Root: $flutterRoot');

  return FlutterSdkInfo(
    fingerprint: fingerprint,
    flutterRoot: flutterRoot,
    flutterCommand: flutterCommand,
    usedFvm: true,
    configuredVersion: configuredVersion,
  );
}

bool _isValidFlutterRoot(String path) {
  if (path.isEmpty || path == '.' || path == './') return false;
  final root = Directory(path);
  if (!root.existsSync()) return false;
  return File(join(path, 'bin', 'flutter')).existsSync() &&
      File(join(path, 'bin', 'dart')).existsSync();
}

/// Pick absolute `.../bin/flutter` from `which` / `fvm exec which` stdout.
///
/// fvm 3.x prints a banner before the real path, e.g.:
/// ```
/// fvm: Running version: "3.41.9"
///
/// /Users/.../fvm/versions/3.41.9/bin/flutter
/// ```
String? pickFlutterBinPath(String stdout) {
  final lines = stdout
      .trim()
      .split('\n')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty);
  for (final line in lines.toList().reversed) {
    if (line.contains(Platform.pathSeparator) &&
        basename(line) == 'flutter' &&
        !line.contains(' ')) {
      return line;
    }
  }
  return null;
}

Map<String, dynamic> _parseVersionMachineJson(String stdout) {
  final trimmed = stdout.trim();
  // 有些环境下日志会混在前面，尝试截取最后一个 JSON 对象
  final start = trimmed.indexOf('{');
  final end = trimmed.lastIndexOf('}');
  if (start < 0 || end <= start) {
    throw Exception('无法解析 flutter --version --machine 输出: $stdout');
  }
  final decoded = jsonDecode(trimmed.substring(start, end + 1));
  if (decoded is! Map) {
    throw Exception('flutter --version --machine 返回非对象: $stdout');
  }
  return Map<String, dynamic>.from(decoded);
}

Future<String> _resolveFlutterRoot(
  Directory projectDir,
  List<String> flutterCommand,
  bool usedFvm,
) async {
  try {
    final whichCmd = usedFvm
        ? <String>['fvm', 'exec', 'which', 'flutter']
        : <String>['which', 'flutter'];
    final whichResult = await ProcessRunner().runProcess(
      whichCmd,
      workingDirectory: projectDir,
      printOutput: false,
    );
    // fvm exec prefixes stdout with "fvm: Running version: ..." — skip non-path lines.
    final flutterBin = pickFlutterBinPath(whichResult.stdout);
    // Bare names like "flutter" yield File('flutter').parent.parent == "."
    if (flutterBin != null) {
      final root = File(flutterBin).parent.parent.path;
      if (_isValidFlutterRoot(root)) return root;
    }
  } catch (_) {
    // fall through
  }

  // Local FVM symlink: <project>/.fvm/flutter_sdk
  final fvmSdkLink = join(projectDir.path, '.fvm', 'flutter_sdk');
  if (_isValidFlutterRoot(fvmSdkLink)) {
    return Directory(fvmSdkLink).resolveSymbolicLinksSync();
  }

  final doctor = await ProcessRunner().runProcess(
    [...flutterCommand, 'doctor', '-v'],
    workingDirectory: projectDir,
    printOutput: false,
  );
  for (final line in doctor.stdout.split('\n')) {
    final match = RegExp(r'at (/.*)').firstMatch(line);
    if (match != null && line.contains('Flutter version')) {
      final root = match.group(1)!.trim();
      if (_isValidFlutterRoot(root)) return root;
    }
  }
  throw Exception('无法解析 Flutter SDK 根目录');
}

File _fingerprintFile(String projectPath) {
  final home = readEnv('HOME');
  final key = base64Url.encode(utf8.encode(projectPath)).replaceAll('=', '');
  return File(join(home, '.metax', 'flutter_sdk', '$key.json'));
}

Future<String?> readLastFlutterSdkFingerprint(String projectPath) async {
  final file = _fingerprintFile(projectPath);
  if (!file.existsSync()) return null;
  try {
    final json = jsonDecode(await file.readAsString());
    if (json is Map && json['fingerprint'] is String) {
      return json['fingerprint'] as String;
    }
  } catch (_) {
    return null;
  }
  return null;
}

Future<void> saveFlutterSdkFingerprint({
  required String projectPath,
  required FlutterSdkInfo sdk,
}) async {
  final file = _fingerprintFile(projectPath);
  await file.parent.create(recursive: true);
  await file.writeAsString(
    const JsonEncoder.withIndent('  ').convert({
      'fingerprint': sdk.fingerprint,
      'flutterRoot': sdk.flutterRoot,
      'usedFvm': sdk.usedFvm,
      'configuredVersion': sdk.configuredVersion,
      'projectPath': projectPath,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    }),
  );
}

/// 版本变化时清理工程内 Flutter 构建缓存（不清理全局 pub-cache）
Future<void> cleanFlutterProjectCaches({
  required Directory projectDir,
  required FlutterSdkInfo sdk,
}) async {
  loggerWarning('🧹 Flutter SDK 版本变化，清理工程构建缓存（保留 pub-cache）...');

  try {
    await ProcessRunner().runProcess(
      [...sdk.flutterCommand, 'clean'],
      workingDirectory: projectDir,
      printOutput: true,
    );
  } catch (e) {
    loggerWarning('flutter clean 失败，继续删除本地目录: $e');
  }

  final dirsToDelete = [
    Directory(join(projectDir.path, 'build')),
    Directory(join(projectDir.path, '.dart_tool')),
    Directory(join(projectDir.path, '.ios', 'Pods')),
    Directory(join(projectDir.path, '.ios', '.symlinks')),
    Directory(join(projectDir.path, '.android')),
  ];
  for (final dir in dirsToDelete) {
    if (await dir.exists()) {
      await dir.delete(recursive: true);
      loggerDebug('已删除: ${dir.path}');
    }
  }

  final podfileLock = File(join(projectDir.path, '.ios', 'Podfile.lock'));
  if (await podfileLock.exists()) {
    await podfileLock.delete();
    loggerDebug('已删除: ${podfileLock.path}');
  }
}

/// 打包前版本闸门：对齐 FVM → 解析 SDK → 变化则清理
Future<FlutterSdkGateResult> ensureFlutterSdkReady(
  Directory projectDir,
) async {
  await ensureFvmFlutterReady(projectDir);
  final sdk = await resolveFlutterSdk(projectDir);
  final last = await readLastFlutterSdkFingerprint(projectDir.path);
  if (last == null) {
    loggerInfo('🔍 首次记录 Flutter SDK 指纹: ${sdk.fingerprint}');
    await saveFlutterSdkFingerprint(projectPath: projectDir.path, sdk: sdk);
    return FlutterSdkGateResult(sdk: sdk, didClean: false);
  }
  if (last == sdk.fingerprint) {
    loggerInfo('✅ Flutter SDK 未变化 (${sdk.fingerprint})，跳过清理缓存');
    return FlutterSdkGateResult(sdk: sdk, didClean: false);
  }

  loggerWarning('⚠️ Flutter SDK 变化: $last -> ${sdk.fingerprint}');
  await cleanFlutterProjectCaches(projectDir: projectDir, sdk: sdk);
  await saveFlutterSdkFingerprint(projectPath: projectDir.path, sdk: sdk);
  return FlutterSdkGateResult(sdk: sdk, didClean: true);
}
