import 'dart:io';

import 'package:meta_tool/app_home_dir.dart';
import 'package:meta_tool/common.dart';
import 'package:path/path.dart' as p;
import 'package:process_runner/process_runner.dart';

class PatchCompatIssue {
  final String repo;
  final String path;
  final String reason;

  const PatchCompatIssue({
    required this.repo,
    required this.path,
    required this.reason,
  });

  @override
  String toString() => '- [$repo] $path（$reason）';
}

/// 单个仓库相对发版基线的对比目标（含工作区未提交改动）。
class PatchRepoBaseline {
  /// 展示名，如 `metaapp_flutter` / `unity`
  final String label;

  /// git 工作目录
  final String workingDirectory;

  /// 发版时该仓库的 commit
  final String baseCommit;

  /// 路径分类时的逻辑前缀（一般等于 submodule path）
  final String pathPrefix;

  /// Unity 仓库：任意实质改动均不可热更
  final bool isUnity;

  const PatchRepoBaseline({
    required this.label,
    required this.workingDirectory,
    required this.baseCommit,
    this.pathPrefix = '',
    this.isUnity = false,
  });
}

class PatchCompatResult {
  final bool ok;
  final List<PatchCompatIssue> issues;
  final List<PatchRepoBaseline> baselines;

  const PatchCompatResult({
    required this.ok,
    required this.issues,
    required this.baselines,
  });

  String abortMessage() {
    final buffer = StringBuffer()
      ..writeln('热更中断：检测到不支持 Shorebird 热更的改动，请重新出包（metax upload build_upload_*）。')
      ..writeln()
      ..writeln('对比仓库（发版基线 → 当前工作区，含未提交）：');
    for (final b in baselines) {
      buffer.writeln('- ${b.label}: ${b.baseCommit}');
    }
    buffer
      ..writeln()
      ..writeln('不支持的改动：');
    for (final issue in issues) {
      buffer.writeln(issue);
    }
    buffer
      ..writeln()
      ..writeln('可热更范围：各 Flutter/Dart 仓库内的 Dart 代码（及无原生变更的纯 Dart 依赖）。')
      ..writeln('Unity / 宿主原生 / assets / 引擎版本变更必须走完整发版。')
      ..writeln('排障可加 --force-patch 跳过预审（危险）。');
    return buffer.toString();
  }
}

/// 对照发版时各仓库 commit，拦截不可热更改动（多仓库 + 未提交）。
class PatchCompatGate {
  PatchCompatGate(this.appHomeDir);

  final AppHomeDir appHomeDir;

  Future<PatchCompatResult> check(List<PatchRepoBaseline> baselines) async {
    // 根仓库对比时跳过已单独建基线的 submodule 路径（避免 gitlink 误报）。
    final coveredRoots = baselines
        .map((b) => b.pathPrefix.replaceAll('\\', '/').trim())
        .where((p) => p.isNotEmpty)
        .toSet();

    final issues = <PatchCompatIssue>[];
    for (final baseline in baselines) {
      issues.addAll(await _checkRepo(
        baseline,
        skipPathRoots: baseline.pathPrefix.isEmpty ? coveredRoots : const {},
      ));
    }
    return PatchCompatResult(
      ok: issues.isEmpty,
      issues: issues,
      baselines: baselines,
    );
  }

  Future<List<PatchCompatIssue>> _checkRepo(
    PatchRepoBaseline baseline, {
    Set<String> skipPathRoots = const {},
  }) async {
    final dir = Directory(baseline.workingDirectory);
    if (!dir.existsSync()) {
      return [
        PatchCompatIssue(
          repo: baseline.label,
          path: baseline.workingDirectory,
          reason: '本地仓库目录不存在',
        ),
      ];
    }

    try {
      await ProcessRunner().runProcess(
        ['git', 'rev-parse', '--verify', '${baseline.baseCommit}^{commit}'],
        workingDirectory: dir,
        printOutput: false,
      );
    } catch (_) {
      return [
        PatchCompatIssue(
          repo: baseline.label,
          path: baseline.baseCommit,
          reason: '本地找不到发版基线 commit（可能未 fetch）',
        ),
      ];
    }

    final paths = await _changedPathsIncludingUncommitted(
      workingDirectory: dir,
      baseCommit: baseline.baseCommit,
    );

    final issues = <PatchCompatIssue>[];
    for (final path in paths) {
      final rel = path.replaceAll('\\', '/');
      if (_isUnderSkippedRoot(rel, skipPathRoots)) {
        continue;
      }
      final reason = classifyPath(
        path,
        pathPrefix: baseline.pathPrefix,
        isUnity: baseline.isUnity,
      );
      if (reason != null) {
        issues.add(PatchCompatIssue(
          repo: baseline.label,
          path: path,
          reason: reason,
        ));
      }
    }
    return issues;
  }

  static bool _isUnderSkippedRoot(String rel, Set<String> skipPathRoots) {
    for (final root in skipPathRoots) {
      if (rel == root || rel.startsWith('$root/')) return true;
    }
    return false;
  }

  /// 相对 baseCommit：已提交差异 + 暂存/未暂存 + 未跟踪文件。
  Future<List<String>> _changedPathsIncludingUncommitted({
    required Directory workingDirectory,
    required String baseCommit,
  }) async {
    final runner = ProcessRunner();
    final diffOut = (await runner.runProcess(
      ['git', 'diff', '--name-only', baseCommit],
      workingDirectory: workingDirectory,
      printOutput: false,
    ))
        .stdout
        .toString();

    final untrackedOut = (await runner.runProcess(
      ['git', 'ls-files', '-o', '--exclude-standard'],
      workingDirectory: workingDirectory,
      printOutput: false,
    ))
        .stdout
        .toString();

    final set = <String>{};
    for (final line in [...diffOut.split('\n'), ...untrackedOut.split('\n')]) {
      final path = line.trim();
      if (path.isNotEmpty) set.add(path);
    }
    return set.toList()..sort();
  }

  /// 返回 null 表示可热更（或可忽略）；非 null 为拦截原因。
  ///
  /// [path] 为相对该仓库根的路径；[pathPrefix] 为 submodule 在 workspace 中的路径。
  static String? classifyPath(
    String path, {
    String pathPrefix = '',
    bool isUnity = false,
  }) {
    final rel = path.replaceAll('\\', '/');
    if (rel.isEmpty) return null;

    if (rel.endsWith('.md') ||
        rel.startsWith('.github/') ||
        rel.contains('/.git/') ||
        rel.endsWith('.gitignore')) {
      return null;
    }

    if (isUnity) {
      return 'Unity 相关';
    }

    final prefixed = pathPrefix.isEmpty
        ? rel
        : p.posix.join(pathPrefix.replaceAll('\\', '/'), rel);
    final lower = prefixed.toLowerCase();

    if (prefixed.startsWith('ios/') ||
        prefixed.startsWith('android/') ||
        prefixed.startsWith('ohos/') ||
        rel.startsWith('ios/') ||
        rel.startsWith('android/') ||
        rel.startsWith('ohos/')) {
      return '宿主原生工程';
    }

    if (lower.contains('unityandroid') ||
        lower.contains('unitylibrary') ||
        prefixed.startsWith('unity/') ||
        prefixed.contains('/unity/') ||
        lower.contains('unity-hot') ||
        prefixed.startsWith('Unity')) {
      return 'Unity 相关';
    }

    if (rel.endsWith('.fvmrc') ||
        rel.endsWith('fvm_config.json') ||
        prefixed.endsWith('.fvmrc') ||
        prefixed.endsWith('fvm_config.json')) {
      return 'Flutter 引擎/FVM 版本';
    }

    if (rel.endsWith('shorebird.yaml')) {
      return 'Shorebird 配置变更';
    }

    if (RegExp(r'\.(png|jpg|jpeg|webp|gif|svg|ttf|otf)$', caseSensitive: false)
        .hasMatch(rel)) {
      return '资源文件';
    }

    if (rel.contains('/assets/') ||
        rel.startsWith('assets/') ||
        prefixed.contains('/assets/')) {
      if (rel.endsWith('.dart') ||
          rel.endsWith('dart_define.json') ||
          rel.endsWith('.yaml') ||
          rel.endsWith('.yml')) {
        return null;
      }
      return '资源文件';
    }

    if (rel.endsWith('.dart') ||
        rel.endsWith('pubspec.yaml') ||
        rel.endsWith('pubspec.lock') ||
        rel.endsWith('dart_define.json') ||
        rel.endsWith('analysis_options.yaml')) {
      return null;
    }

    if (rel.contains('/ios/') ||
        rel.contains('/android/') ||
        rel.contains('/macos/') ||
        rel.contains('/windows/') ||
        rel.contains('/linux/') ||
        rel.endsWith('.podspec') ||
        rel.endsWith('.gradle') ||
        rel.endsWith('.so') ||
        rel.endsWith('.a') ||
        rel.endsWith('.jar') ||
        rel.endsWith('.aar') ||
        rel.contains('/jni/')) {
      return '含原生/插件工程文件';
    }

    if (rel == 'melos.yaml' || rel.endsWith('/melos.yaml')) {
      return 'melos 工作区配置';
    }

    if (rel.endsWith('.yaml') || rel.endsWith('.yml') || rel.endsWith('.json')) {
      return null;
    }

    return '非 Dart 热更改动';
  }

  Future<void> assertCompatible(List<PatchRepoBaseline> baselines) async {
    if (baselines.isEmpty) {
      throw Exception(
        '热更预审没有可对比的仓库基线（打包记录缺少 submodule / Unity commit）。'
        '排障可加 --force-patch。',
      );
    }
    final result = await check(baselines);
    if (!result.ok) {
      loggerError(result.abortMessage());
      throw Exception(result.abortMessage());
    }
    final labels = baselines.map((e) => e.label).join(', ');
    loggerSuccess(
      'PatchCompatGate 通过：已对比 ${baselines.length} 个仓库（$labels），'
      '相对发版基线仅检测到可热更改动',
    );
  }
}
