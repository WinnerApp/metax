import 'package:meta_tool/app_home_dir.dart';
import 'package:meta_tool/common.dart';
import 'package:process_runner/process_runner.dart';

class PatchCompatIssue {
  final String path;
  final String reason;

  const PatchCompatIssue(this.path, this.reason);

  @override
  String toString() => '- $path（$reason）';
}

class PatchCompatResult {
  final bool ok;
  final List<PatchCompatIssue> issues;
  final String baseCommit;
  final String headCommit;

  const PatchCompatResult({
    required this.ok,
    required this.issues,
    required this.baseCommit,
    required this.headCommit,
  });

  String abortMessage() {
    final buffer = StringBuffer()
      ..writeln('热更中断：检测到不支持 Shorebird 热更的改动，请重新出包（metax upload build_upload_*）。')
      ..writeln()
      ..writeln('基线: $baseCommit')
      ..writeln('当前: $headCommit')
      ..writeln()
      ..writeln('不支持的改动：');
    for (final issue in issues) {
      buffer.writeln(issue);
    }
    buffer
      ..writeln()
      ..writeln('可热更范围：仅 Dart 代码（及无原生变更的纯 Dart 依赖）。')
      ..writeln('Unity / 原生 / assets / 引擎版本变更必须走完整发版。');
    return buffer.toString();
  }
}

/// 对照 release 基线 commit，拦截不可热更改动。
class PatchCompatGate {
  PatchCompatGate(this.appHomeDir);

  final AppHomeDir appHomeDir;

  Future<PatchCompatResult> check({
    required String baseCommit,
    String headRef = 'HEAD',
  }) async {
    final workspace = appHomeDir.directory;
    final headCommit = (await ProcessRunner().runProcess(
      ['git', 'rev-parse', headRef],
      workingDirectory: workspace,
      printOutput: false,
    ))
        .stdout
        .toString()
        .trim();

    final diffOut = (await ProcessRunner().runProcess(
      ['git', 'diff', '--name-only', baseCommit, headCommit],
      workingDirectory: workspace,
      printOutput: false,
    ))
        .stdout
        .toString();

    final paths = diffOut
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    final issues = <PatchCompatIssue>[];
    for (final path in paths) {
      final reason = classifyPath(path);
      if (reason != null) {
        issues.add(PatchCompatIssue(path, reason));
      }
    }

    return PatchCompatResult(
      ok: issues.isEmpty,
      issues: issues,
      baseCommit: baseCommit,
      headCommit: headCommit,
    );
  }

  /// 返回 null 表示可热更（或可忽略）；非 null 为拦截原因
  static String? classifyPath(String path) {
    final p = path.replaceAll('\\', '/');

    if (p.endsWith('.md') ||
        p.startsWith('.github/') ||
        p.contains('/.git/') ||
        p.endsWith('.gitignore')) {
      return null;
    }

    if (p.startsWith('ios/') ||
        p.startsWith('android/') ||
        p.startsWith('ohos/')) {
      return '宿主原生工程';
    }

    final lower = p.toLowerCase();
    if (lower.contains('unityandroid') ||
        lower.contains('unitylibrary') ||
        p.startsWith('unity/') ||
        p.contains('/unity/') ||
        lower.contains('unity-hot') ||
        p.startsWith('Unity')) {
      return 'Unity 相关';
    }

    if (p.endsWith('.fvmrc') || p.endsWith('fvm_config.json')) {
      return 'Flutter 引擎/FVM 版本';
    }

    if (p.endsWith('shorebird.yaml')) {
      return 'Shorebird 配置变更';
    }

    if (RegExp(r'\.(png|jpg|jpeg|webp|gif|svg|ttf|otf)$', caseSensitive: false)
        .hasMatch(p)) {
      return '资源文件';
    }

    if (p.contains('/assets/') || p.startsWith('assets/')) {
      if (p.endsWith('.dart') ||
          p.endsWith('dart_define.json') ||
          p.endsWith('.yaml') ||
          p.endsWith('.yml')) {
        return null;
      }
      return '资源文件';
    }

    if (p.endsWith('.dart') ||
        p.endsWith('pubspec.yaml') ||
        p.endsWith('pubspec.lock') ||
        p.endsWith('dart_define.json') ||
        p.endsWith('analysis_options.yaml')) {
      return null;
    }

    if (p.contains('/ios/') ||
        p.contains('/android/') ||
        p.contains('/macos/') ||
        p.contains('/windows/') ||
        p.contains('/linux/') ||
        p.endsWith('.podspec') ||
        p.endsWith('.gradle') ||
        p.endsWith('.so') ||
        p.endsWith('.a') ||
        p.endsWith('.jar') ||
        p.endsWith('.aar') ||
        p.contains('/jni/')) {
      return '含原生/插件工程文件';
    }

    if (p == 'melos.yaml' || p.endsWith('/melos.yaml')) {
      return 'melos 工作区配置';
    }

    if (p.startsWith('metaapp_flutter/')) {
      if (p.endsWith('.yaml') || p.endsWith('.yml') || p.endsWith('.json')) {
        return null;
      }
      return 'Flutter 模块内非 Dart 变更';
    }

    return '非 Dart 热更改动';
  }

  Future<void> assertCompatible({
    required String baseCommit,
    String headRef = 'HEAD',
  }) async {
    final result = await check(baseCommit: baseCommit, headRef: headRef);
    if (!result.ok) {
      loggerError(result.abortMessage());
      throw Exception(result.abortMessage());
    }
    loggerSuccess(
      'PatchCompatGate 通过：相对 $baseCommit 仅检测到可热更改动',
    );
  }
}
