import 'dart:convert';
import 'dart:io';

import 'package:meta_tool/common.dart';
import 'package:path/path.dart' as p;

/// 项目级缓存产物补丁引擎（配置驱动）
///
/// metax 不内置任何项目特定规则；补丁规则完全由项目侧配置文件驱动：
///   <workspace>/metax.cache_patch.json
///
/// 配置文件不存在或解析失败时静默跳过，保证 metax 作为通用工具
/// 可以为任意项目服务，不被特定项目绑定。
///
/// 配置格式：
/// {
///   "version": 1,
///   "rules": [
///     {
///       "name": "规则名（仅日志展示用）",
///       "glob": "相对解压产物的路径，支持 ** 递归，如 KSCrash.podspec / Measure.xcframework/**/*.swiftinterface",
///       "replacements": [
///         {
///           "pattern": "字面量或正则表达式",
///           "replacement": "替换内容，正则模式支持 $1 捕获组",
///           "regex": true,        // 可选，默认 false 按字面量替换
///           "multiLine": true,    // 可选，仅 regex=true 时生效
///           "firstOnly": true     // 可选，默认 false 全部替换
///         }
///       ]
///     }
///   ]
/// }
class CachePatchEngine {
  final Directory workspace;

  static const String configFileName = 'metax.cache_patch.json';

  CachePatchEngine(this.workspace);

  /// 对解压产物目录 [targetDir] 应用项目配置中的全部补丁规则。
  /// 返回实际修改的文件数（幂等：内容未变化不计数）。
  Future<int> apply(Directory targetDir) async {
    final configFile = File(p.join(workspace.path, configFileName));
    if (!await configFile.exists()) {
      loggerDebug('未找到项目补丁配置 ${configFile.path}，跳过补丁');
      return 0;
    }

    final Map<String, dynamic> config;
    try {
      config =
          jsonDecode(await configFile.readAsString()) as Map<String, dynamic>;
    } catch (e) {
      loggerWarning('解析补丁配置 ${configFile.path} 失败: $e');
      return 0;
    }

    final rules = (config['rules'] as List? ?? [])
        .whereType<Map>()
        .map((e) => CachePatchRule.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    if (rules.isEmpty) {
      loggerDebug('补丁配置 ${configFile.path} 未声明任何规则，跳过');
      return 0;
    }

    var patchedFiles = 0;
    for (final rule in rules) {
      final files = await _matchFiles(targetDir, rule.glob);
      if (files.isEmpty) {
        loggerDebug('规则「${rule.name}」未匹配到文件: ${rule.glob}');
        continue;
      }
      for (final file in files) {
        var content = await file.readAsString();
        final before = content;
        for (final r in rule.replacements) {
          content = r.apply(content);
        }
        if (content != before) {
          await file.writeAsString(content);
          patchedFiles++;
          loggerInfo('已按规则「${rule.name}」修复: ${file.path}');
        }
      }
    }
    return patchedFiles;
  }

  /// 在 [root] 下按 glob 匹配文件。
  /// 支持 `**`（递归任意层）与 `*`（单层内任意字符，不跨 /）。
  Future<List<File>> _matchFiles(Directory root, String glob) async {
    final normalizedGlob = glob.replaceAll('\\', '/');
    final files = <File>[];
    if (!normalizedGlob.contains('**')) {
      final f = File(p.join(root.path, normalizedGlob));
      if (await f.exists()) files.add(f);
      return files;
    }
    final regex = _globToRegExp(normalizedGlob);
    await for (final entity in root.list(recursive: true)) {
      if (entity is! File) continue;
      final rel = p.relative(entity.path, from: root.path).replaceAll('\\', '/');
      if (regex.hasMatch(rel)) files.add(entity);
    }
    return files;
  }

  RegExp _globToRegExp(String glob) {
    final sb = StringBuffer(r'^');
    var i = 0;
    while (i < glob.length) {
      final c = glob[i];
      if (c == '*') {
        if (i + 1 < glob.length && glob[i + 1] == '*') {
          sb.write(r'.*');
          i += 2;
        } else {
          sb.write(r'[^/]*');
          i += 1;
        }
      } else if (RegExp(r'[.+^${}()|\[\]\\]').hasMatch(c)) {
        sb.write('\\$c');
        i += 1;
      } else {
        sb.write(c);
        i += 1;
      }
    }
    sb.write(r'$');
    return RegExp(sb.toString());
  }
}

class CachePatchRule {
  final String name;
  final String glob;
  final List<CachePatchReplacement> replacements;

  CachePatchRule({
    required this.name,
    required this.glob,
    required this.replacements,
  });

  factory CachePatchRule.fromJson(Map<String, dynamic> json) => CachePatchRule(
        name: json['name'] as String? ?? (json['glob'] as String? ?? ''),
        glob: json['glob'] as String,
        replacements: (json['replacements'] as List? ?? [])
            .whereType<Map>()
            .map((e) => CachePatchReplacement.fromJson(
                Map<String, dynamic>.from(e)))
            .toList(),
      );
}

class CachePatchReplacement {
  final String pattern;
  final String replacement;
  final bool regex;
  final bool multiLine;
  final bool firstOnly;

  CachePatchReplacement({
    required this.pattern,
    required this.replacement,
    this.regex = false,
    this.multiLine = false,
    this.firstOnly = false,
  });

  factory CachePatchReplacement.fromJson(Map<String, dynamic> json) =>
      CachePatchReplacement(
        pattern: json['pattern'] as String,
        replacement: json['replacement'] as String? ?? '',
        regex: json['regex'] as bool? ?? false,
        multiLine: json['multiLine'] as bool? ?? false,
        firstOnly: json['firstOnly'] as bool? ?? false,
      );

  String apply(String content) {
    if (regex) {
      final re = RegExp(pattern, multiLine: multiLine);
      if (firstOnly) {
        return content.replaceFirstMapped(re, (m) => _expand(m, replacement));
      }
      return content.replaceAllMapped(re, (m) => _expand(m, replacement));
    }
    return firstOnly
        ? content.replaceFirst(pattern, replacement)
        : content.replaceAll(pattern, replacement);
  }

  /// 展开替换模板中的捕获组引用：$1 / $2 ...（以及 $& 表示整个匹配）。
  static String _expand(Match m, String template) {
    return template.replaceAllMapped(RegExp(r'\$(\d+)|\$&'), (g) {
      if (g.group(1) != null) {
        final idx = int.parse(g.group(1)!);
        if (idx >= 1 && idx <= m.groupCount && m.group(idx) != null) {
          return m.group(idx)!;
        }
        return '';
      }
      return m.group(0)!;
    });
  }
}
