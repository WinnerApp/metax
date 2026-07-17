import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:meta_tool/common.dart';
import 'package:path/path.dart';
import 'package:process_runner/process_runner.dart';

/// 校验已打出的 Flutter Framework / AAR 是否与期望 Engine 一致。
///
/// 支持两种 iOS 集成形态：
/// - 本地 Flutter.xcframework
/// - 仅 Flutter.podspec（CocoaPods 拉取官方 engine 产物）
///
/// 示例:
///   metax flutter verify /path/to/frameworks/flutter/Release
///   metax flutter verify --dir /path/to/build/ios/framework/Release
///   metax flutter verify /path/to/aar/flutter --expect-engine abcdef1234...
///   metax flutter verify /path/to/Release --sdk /Users/me/fvm/versions/3.41.9
class VerifyFlutterFrameworkCommand extends Command {
  @override
  String get description =>
      '校验 Flutter Framework/AAR 产物（含官方 Flutter.podspec 依赖）与 Engine 是否一致';

  @override
  String get name => 'verify';

  late ProcessRunner _runner;

  VerifyFlutterFrameworkCommand() {
    argParser.addOption(
      'dir',
      abbr: 'd',
      help: '产物目录（也可作为位置参数传入）',
    );
    argParser.addOption(
      'expect-engine',
      help: '期望的 engineRevision（40 位 hash）；不传则从当前 Flutter SDK 读取',
    );
    argParser.addOption(
      'sdk',
      help: '用于对照的 Flutter SDK 根目录；不传则用 fvm flutter / PATH 中的 flutter',
    );
    argParser.addFlag(
      'strict',
      help: '严格模式：无法从产物提取 engine 时直接失败（默认仅警告）',
      defaultsTo: false,
      negatable: false,
    );
  }

  @override
  Future<void> run() async {
    _runner = ProcessRunner();
    final artifactDir = _resolveArtifactDir();
    final strict = argResults!['strict'] as bool;

    loggerInfo('产物目录: ${artifactDir.path}');

    final kind = _detectArtifactKind(artifactDir);
    loggerInfo('产物类型: ${kind.label}');

    final structureIssues = await _checkStructure(artifactDir, kind);
    for (final issue in structureIssues) {
      loggerError(issue);
    }

    final artifactMeta = await _extractArtifactMeta(artifactDir, kind);
    final artifactEngine = artifactMeta?.engineRevision;
    if (artifactEngine == null || artifactEngine.isEmpty) {
      final msg = '未能从产物中提取 engineRevision';
      if (strict) {
        throw Exception(msg);
      }
      loggerWarning(msg);
    } else {
      loggerInfo('产物 engineRevision = $artifactEngine');
    }
    if (artifactMeta?.flutterVersion != null) {
      loggerInfo('产物 Flutter 版本 = ${artifactMeta!.flutterVersion}');
    }

    final expected = await _resolveExpectedEngine();
    loggerInfo(
      '期望 engineRevision = ${expected.engineRevision}'
      ' (${expected.flutterVersion.isEmpty ? 'manual' : expected.flutterVersion}'
      '@${expected.source})',
    );

    final mismatches = <String>[];
    mismatches.addAll(structureIssues);

    if (artifactEngine != null &&
        artifactEngine.isNotEmpty &&
        artifactEngine != expected.engineRevision) {
      mismatches.add(
        'Engine 不一致: 产物=$artifactEngine, 期望=${expected.engineRevision}',
      );
    }

    final artifactVersion = artifactMeta?.flutterVersion;
    if (artifactVersion != null &&
        expected.flutterVersion.isNotEmpty &&
        !_flutterVersionCompatible(artifactVersion, expected.flutterVersion)) {
      mismatches.add(
        'Flutter 版本不一致: 产物=$artifactVersion, 期望=${expected.flutterVersion}',
      );
    }

    if (mismatches.isEmpty) {
      loggerSuccess(
        '校验通过: ${expected.flutterVersion.isEmpty ? '' : '${expected.flutterVersion}@'}'
        '${expected.engineRevision} (${kind.label})',
      );
      return;
    }

    for (final m in mismatches) {
      loggerError(m);
    }
    throw Exception('校验失败，共 ${mismatches.length} 项不一致');
  }

  Directory _resolveArtifactDir() {
    final option = argResults!['dir'] as String?;
    final rest = argResults!.rest;
    final raw = (option != null && option.trim().isNotEmpty)
        ? option.trim()
        : (rest.isNotEmpty ? rest.first.trim() : '');
    if (raw.isEmpty) {
      throw UsageException(
        '必须指定产物目录，例如:\n'
        '  metax flutter verify /path/to/frameworks/flutter/Release\n'
        '  metax flutter verify --dir /path/to/build/ios/framework/Release',
        usage,
      );
    }
    final dir = Directory(raw);
    if (!dir.existsSync()) {
      throw Exception('产物目录不存在: ${dir.path}');
    }
    return dir;
  }

  _ArtifactKind _detectArtifactKind(Directory dir) {
    final flutterXc = Directory(join(dir.path, 'Flutter.xcframework'));
    final appXc = Directory(join(dir.path, 'App.xcframework'));
    final flutterPodspec = File(join(dir.path, 'Flutter.podspec'));
    if (flutterXc.existsSync() ||
        appXc.existsSync() ||
        flutterPodspec.existsSync()) {
      return _ArtifactKind.iosFramework;
    }

    // 常见路径: aar/flutter 或 outputs/repo
    final hasAar = dir
        .listSync(recursive: false)
        .any((e) => e.path.endsWith('.aar') || basename(e.path) == 'outputs');
    final repoHint = Directory(join(dir.path, 'outputs', 'repo'));
    if (hasAar || repoHint.existsSync()) {
      return _ArtifactKind.androidAar;
    }

    // 宿主集成目录: frameworks/flutter/Release 可能只有 podspec + xcframework
    final hasXcframework = dir.listSync().any(
          (e) => e is Directory && e.path.endsWith('.xcframework'),
        );
    if (hasXcframework) {
      return _ArtifactKind.iosFramework;
    }

    throw Exception(
      '无法识别产物类型（需要含 App.xcframework / Flutter.podspec / Flutter.xcframework，'
      '或 Android aar/outputs）: ${dir.path}',
    );
  }

  Future<List<String>> _checkStructure(
    Directory dir,
    _ArtifactKind kind,
  ) async {
    final issues = <String>[];
    switch (kind) {
      case _ArtifactKind.iosFramework:
        final flutterXc =
            Directory(join(dir.path, 'Flutter.xcframework'));
        final flutterPodspec = File(join(dir.path, 'Flutter.podspec'));
        final appXc = Directory(join(dir.path, 'App.xcframework'));

        // 业务常见两种形态：
        // 1) 本地打出 Flutter.xcframework
        // 2) 仅保留 Flutter.podspec，CocoaPods 拉取官方 engine 产物
        if (await flutterXc.exists()) {
          final binary = await _findIosFlutterBinary(flutterXc);
          if (binary == null) {
            issues.add('Flutter.xcframework 内未找到 Flutter 二进制');
          } else if (await binary.length() == 0) {
            issues.add('Flutter 二进制为空: ${binary.path}');
          } else {
            loggerInfo('Flutter 二进制: ${binary.path}');
          }
        } else if (await flutterPodspec.exists()) {
          loggerInfo(
            '未找到 Flutter.xcframework，使用官方产物依赖: ${flutterPodspec.path}',
          );
        } else {
          issues.add('缺少 Flutter.xcframework 且缺少 Flutter.podspec');
        }

        if (!await appXc.exists()) {
          issues.add('缺少 App.xcframework');
        } else {
          final assets = await _findAppFlutterAssets(appXc);
          if (assets == null) {
            issues.add('App.xcframework 内未找到 flutter_assets');
          } else {
            loggerInfo('flutter_assets: ${assets.path}');
          }
        }
        break;
      case _ArtifactKind.androidAar:
        final repo = await _resolveAndroidRepoDir(dir);
        if (repo == null) {
          issues.add('未找到 Android Maven repo（outputs/repo）或 .aar 文件');
        } else {
          loggerInfo('Android repo: ${repo.path}');
        }
        break;
    }
    return issues;
  }

  Future<_ArtifactMeta?> _extractArtifactMeta(
    Directory dir,
    _ArtifactKind kind,
  ) async {
    switch (kind) {
      case _ArtifactKind.iosFramework:
        return _extractIosMeta(dir);
      case _ArtifactKind.androidAar:
        final engine = await _extractAndroidEngine(dir);
        if (engine == null) return null;
        return _ArtifactMeta(engineRevision: engine);
    }
  }

  Future<_ArtifactMeta?> _extractIosMeta(Directory dir) async {
    // 优先从 Flutter.podspec 的官方下载 URL 解析（你们当前集成方式）
    final fromPodspec = await _extractMetaFromFlutterPodspec(dir);
    if (fromPodspec != null) return fromPodspec;

    final flutterXc = Directory(join(dir.path, 'Flutter.xcframework'));
    if (!await flutterXc.exists()) return null;
    final binary = await _findIosFlutterBinary(flutterXc);
    if (binary == null) return null;

    // Flutter.framework 二进制内嵌 40 位 engine git hash
    try {
      final result = await _runner.runProcess(
        ['strings', '-a', binary.path],
        printOutput: false,
      );
      final hashes = RegExp(r'\b[0-9a-f]{40}\b')
          .allMatches(result.stdout)
          .map((m) => m.group(0)!)
          .toSet()
          .toList();
      if (hashes.isEmpty) return null;
      if (hashes.length == 1) {
        return _ArtifactMeta(engineRevision: hashes.first);
      }

      // 多个 hash 时优先匹配当前期望 engine（若已能拿到）
      final expectOpt = argResults!['expect-engine'] as String?;
      if (expectOpt != null && hashes.contains(expectOpt.trim())) {
        return _ArtifactMeta(engineRevision: expectOpt.trim());
      }
      // 常见情况：engine hash 会出现多次；取出现次数最多的
      final counts = <String, int>{};
      for (final m in RegExp(r'\b[0-9a-f]{40}\b').allMatches(result.stdout)) {
        final h = m.group(0)!;
        counts[h] = (counts[h] ?? 0) + 1;
      }
      final sorted = counts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      loggerInfo(
        '从 Flutter 二进制解析到多个 hash，选用频次最高: '
        '${sorted.first.key} (x${sorted.first.value})',
      );
      return _ArtifactMeta(engineRevision: sorted.first.key);
    } catch (e) {
      loggerWarning('strings 解析 Flutter 二进制失败: $e');
      return null;
    }
  }

  /// 从 Flutter.podspec 提取 engineRevision 与 Flutter 版本。
  ///
  /// 官方产物 URL 形如:
  ///   .../flutter/<engineHash>/ios/...
  ///   .../flutter/<engineHash>/ios-release/...
  /// pod 版本约定: major.minor.(patch * 100 + hotfix) → 如 3.41.900 = 3.41.9
  Future<_ArtifactMeta?> _extractMetaFromFlutterPodspec(Directory dir) async {
    final candidates = [
      File(join(dir.path, 'Flutter.podspec')),
      File(join(dir.path, 'Flutter.podspec.json')),
    ];
    for (final file in candidates) {
      if (!await file.exists()) continue;
      final content = await file.readAsString();
      loggerInfo('读取: ${file.path}');

      String? engine;
      // http(s)://.../flutter/<40hex>/...（含 storage.flutter-io.cn 镜像）
      final urlMatch = RegExp(
        r'https?://\S+/flutter/([0-9a-f]{40})/',
        caseSensitive: false,
      ).firstMatch(content);
      if (urlMatch != null) {
        engine = urlMatch.group(1)!;
        loggerInfo('从 Flutter.podspec URL 解析 engine = $engine');
      } else {
        final hashes = RegExp(r'\b[0-9a-f]{40}\b')
            .allMatches(content)
            .map((m) => m.group(0)!)
            .toSet();
        if (hashes.length == 1) {
          engine = hashes.first;
          loggerInfo('从 Flutter.podspec 解析 engine = $engine');
        } else if (hashes.length > 1) {
          loggerWarning(
            'Flutter.podspec 中发现多个 hash，无法唯一确定 engine: ${hashes.join(', ')}',
          );
        }
      }

      final flutterVersion = _parseFlutterVersionFromPodspec(content);
      if (flutterVersion != null) {
        loggerInfo('从 Flutter.podspec version 解析 Flutter = $flutterVersion');
      }

      if (engine == null) continue;
      return _ArtifactMeta(
        engineRevision: engine,
        flutterVersion: flutterVersion,
      );
    }
    return null;
  }

  /// podspec `s.version = '3.41.900'` → `3.41.9`
  String? _parseFlutterVersionFromPodspec(String content) {
    final match = RegExp(
      r"""s\.version\s*=\s*['"](\d+)\.(\d+)\.(\d+)['"]""",
    ).firstMatch(content);
    if (match == null) return null;
    final major = int.parse(match.group(1)!);
    final minor = int.parse(match.group(2)!);
    final encoded = int.parse(match.group(3)!);
    final patch = encoded ~/ 100;
    final hotfix = encoded % 100;
    if (hotfix == 0) return '$major.$minor.$patch';
    return '$major.$minor.$patch.$hotfix';
  }

  bool _flutterVersionCompatible(String artifact, String expected) {
    if (artifact == expected) return true;
    // 期望 3.41.9 / 3.41.9-xxx 与产物 3.41.9 视为兼容
    return expected == artifact ||
        expected.startsWith('$artifact-') ||
        expected.startsWith('$artifact+');
  }

  Future<String?> _extractAndroidEngine(Directory dir) async {
    final repo = await _resolveAndroidRepoDir(dir);
    if (repo == null) return null;

    // io/flutter/flutter_embedding_release/1.0.0-<engine>/...
    final embeddingRoot = Directory(
      join(repo.path, 'io', 'flutter'),
    );
    if (!await embeddingRoot.exists()) {
      // 也扫目录名里的 40 位 hash
      return _scanEngineHashInTree(dir);
    }

    final hashRe = RegExp(r'1\.0\.0-([0-9a-f]{40})');
    final found = <String>{};
    await for (final entity in embeddingRoot.list(recursive: true)) {
      final name = basename(entity.path);
      final m = hashRe.firstMatch(name);
      if (m != null) {
        found.add(m.group(1)!);
      }
    }
    if (found.isEmpty) {
      return _scanEngineHashInTree(dir);
    }
    if (found.length > 1) {
      loggerWarning('发现多个 embedding engine: ${found.join(', ')}');
    }
    return found.first;
  }

  Future<String?> _scanEngineHashInTree(Directory dir) async {
    final hashRe = RegExp(r'[0-9a-f]{40}');
    final found = <String>{};
    await for (final entity in dir.list(recursive: true)) {
      final name = basename(entity.path);
      if (name.contains('flutter_embedding') ||
          name.contains('armeabi_v7a_release') ||
          name.contains('arm64_v8a_release') ||
          name.contains('x86_64_release') ||
          name.contains('armeabi_v7a_debug') ||
          name.contains('arm64_v8a_debug')) {
        final m = hashRe.firstMatch(name);
        if (m != null) found.add(m.group(0)!);
      }
    }
    if (found.isEmpty) return null;
    return found.first;
  }

  Future<Directory?> _resolveAndroidRepoDir(Directory dir) async {
    final candidates = [
      Directory(join(dir.path, 'outputs', 'repo')),
      Directory(join(dir.path, 'repo')),
      dir,
    ];
    for (final c in candidates) {
      if (!await c.exists()) continue;
      final embedding = Directory(join(c.path, 'io', 'flutter'));
      if (await embedding.exists()) return c;
      final hasAar = c
          .listSync(recursive: false)
          .any((e) => e is File && e.path.endsWith('.aar'));
      if (hasAar) return c;
    }
    return null;
  }

  Future<File?> _findIosFlutterBinary(Directory flutterXc) async {
    // 优先真机 arm64
    final preferred = [
      join(flutterXc.path, 'ios-arm64', 'Flutter.framework', 'Flutter'),
      join(
        flutterXc.path,
        'ios-arm64_x86_64-simulator',
        'Flutter.framework',
        'Flutter',
      ),
    ];
    for (final p in preferred) {
      final f = File(p);
      if (await f.exists()) return f;
    }
    await for (final entity in flutterXc.list(recursive: true)) {
      if (entity is File && basename(entity.path) == 'Flutter') {
        return entity;
      }
    }
    return null;
  }

  Future<Directory?> _findAppFlutterAssets(Directory appXc) async {
    final preferred = Directory(join(
      appXc.path,
      'ios-arm64',
      'App.framework',
      'flutter_assets',
    ));
    if (await preferred.exists()) return preferred;
    await for (final entity in appXc.list(recursive: true)) {
      if (entity is Directory && basename(entity.path) == 'flutter_assets') {
        return entity;
      }
    }
    return null;
  }

  Future<_ExpectedEngine> _resolveExpectedEngine() async {
    final manual = argResults!['expect-engine'] as String?;
    if (manual != null && manual.trim().isNotEmpty) {
      final hash = manual.trim();
      if (!RegExp(r'^[0-9a-f]{40}$').hasMatch(hash)) {
        loggerWarning('expect-engine 不是 40 位 hex: $hash');
      }
      return _ExpectedEngine(
        engineRevision: hash,
        flutterVersion: '',
        source: '--expect-engine',
      );
    }

    final sdkRootOpt = argResults!['sdk'] as String?;
    String? flutterRoot = sdkRootOpt?.trim();
    List<String> flutterCmd;

    if (flutterRoot != null && flutterRoot.isNotEmpty) {
      final bin = File(join(flutterRoot, 'bin', 'flutter'));
      if (!await bin.exists()) {
        throw Exception('无效 SDK 目录（缺少 bin/flutter）: $flutterRoot');
      }
      flutterCmd = [bin.path];
    } else {
      flutterCmd = await _resolveFlutterCommand();
    }

    final result = await _runner.runProcess(
      [...flutterCmd, '--version', '--machine'],
      printOutput: false,
    );
    final json = _parseVersionMachineJson(result.stdout);
    final version =
        (json['flutterVersion'] ?? json['frameworkVersion'] ?? '').toString();
    var engine = (json['engineRevision'] ?? '').toString();
    flutterRoot ??= (json['flutterRoot'] ?? '').toString();

    if (engine.isEmpty && flutterRoot.isNotEmpty) {
      final engineFile =
          File(join(flutterRoot, 'bin', 'internal', 'engine.version'));
      if (await engineFile.exists()) {
        engine = (await engineFile.readAsString()).trim();
      }
    }
    if (engine.isEmpty) {
      throw Exception('无法从 Flutter SDK 读取 engineRevision，请用 --expect-engine 指定');
    }

    // 与 engine.version 文件交叉校验
    if (flutterRoot.isNotEmpty) {
      final engineFile =
          File(join(flutterRoot, 'bin', 'internal', 'engine.version'));
      if (await engineFile.exists()) {
        final fileEngine = (await engineFile.readAsString()).trim();
        loggerInfo('SDK engine.version = $fileEngine');
        if (fileEngine != engine) {
          throw Exception(
            'SDK 自身不一致: flutter --version 的 engineRevision=$engine, '
            'engine.version=$fileEngine',
          );
        }
      }
    }

    return _ExpectedEngine(
      engineRevision: engine,
      flutterVersion: version,
      source: flutterRoot.isEmpty ? 'flutter --version' : flutterRoot,
    );
  }

  Future<List<String>> _resolveFlutterCommand() async {
    try {
      final which = await _runner.runProcess(
        ['which', 'fvm'],
        printOutput: false,
      );
      if (which.stdout.trim().isNotEmpty) {
        return ['fvm', 'flutter'];
      }
    } catch (_) {}
    return ['flutter'];
  }

  Map<String, dynamic> _parseVersionMachineJson(String stdout) {
    final trimmed = stdout.trim();
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
}

enum _ArtifactKind {
  iosFramework('iOS Framework'),
  androidAar('Android AAR');

  final String label;
  const _ArtifactKind(this.label);
}

class _ExpectedEngine {
  final String engineRevision;
  final String flutterVersion;
  final String source;

  const _ExpectedEngine({
    required this.engineRevision,
    required this.flutterVersion,
    required this.source,
  });
}

class _ArtifactMeta {
  final String engineRevision;
  final String? flutterVersion;

  const _ArtifactMeta({
    required this.engineRevision,
    this.flutterVersion,
  });
}
