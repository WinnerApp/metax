import 'dart:convert';
import 'dart:io';

class GitSubmodule {
  String? path;
  String? url;
  String? name;
  String? branch;

  GitSubmodule({
    this.path,
    this.url,
    this.name,
    this.branch,
  });

  factory GitSubmodule.fromJson(Map<String, dynamic> json) {
    return GitSubmodule(
      name: json['name'] as String?,
      path: json['path'] as String?,
      url: json['url'] as String?,
      branch: json['branch'] as String?,
    );
  }

  @override
  String toString() => '''
name = $name
path = $path
url = $url
branch = $branch
''';
}

/// 获取 gitmodules 文件路径
/// 使用新的 JSON 格式路径（workspace/gitmodules.json），如果不存在则抛出异常中止流程
Future<String> getGitmodulesFilePath(String workspace) async {
  // 新的 JSON 格式路径：workspace/gitmodules.json
  final newPath = '$workspace/gitmodules.json';
  final newFile = File(newPath);
  if (!await newFile.exists()) {
    throw Exception('Gitmodules file not found: $newPath');
  }
  return newPath;
}

/// 解析 gitmodules 文件（支持 INI 和 JSON 格式）
Future<List<GitSubmodule>> parseGitmodulesFile(String filePath) async {
  final file = File(filePath);
  if (!await file.exists()) {
    throw Exception('Gitmodules file not found: $filePath');
  }

  final content = await file.readAsString();

  // 尝试解析为 JSON 格式
  try {
    final jsonData = jsonDecode(content);
    if (jsonData is List) {
      // 如果是数组格式
      return jsonData
          .map((item) => GitSubmodule.fromJson(item as Map<String, dynamic>))
          .toList();
    } else if (jsonData is Map) {
      // 如果是对象格式，可能包含 submodules 字段
      if (jsonData.containsKey('submodules')) {
        final submodules = jsonData['submodules'] as List;
        return submodules
            .map((item) => GitSubmodule.fromJson(item as Map<String, dynamic>))
            .toList();
      } else {
        // 直接是对象，尝试转换
        return [GitSubmodule.fromJson(jsonData as Map<String, dynamic>)];
      }
    }
  } catch (e) {
    // 不是 JSON 格式，继续解析 INI 格式
  }

  // 解析 INI 格式（旧的 .gitmodules 格式）
  final submodules = <GitSubmodule>[];
  GitSubmodule? currentSubmodule;

  for (var line in LineSplitter.split(content)) {
    line = line.trim();
    if (line.isEmpty) continue;

    // 匹配 [submodule "name"]
    final moduleMatch = RegExp(r'^\[submodule "(.+)"\]$').firstMatch(line);
    if (moduleMatch != null) {
      final name = moduleMatch.group(1)!;
      currentSubmodule = GitSubmodule()..name = name;
      submodules.add(currentSubmodule);
      continue;
    }

    // 跳过非 submodule 部分
    if (currentSubmodule == null) continue;

    // 匹配 path = ...
    final pathMatch = RegExp(r'^path\s*=\s*(.+)$').firstMatch(line);
    if (pathMatch != null) {
      currentSubmodule.path = pathMatch.group(1)!;
      continue;
    }

    // 匹配 url = ...
    final urlMatch = RegExp(r'^url\s*=\s*(.+)$').firstMatch(line);
    if (urlMatch != null) {
      currentSubmodule.url = urlMatch.group(1)!;
      continue;
    }

    // 匹配 branch = ...
    final branchMatch = RegExp(r'^branch\s*=\s*(.+)$').firstMatch(line);
    if (branchMatch != null) {
      currentSubmodule.branch = branchMatch.group(1)!;
      continue;
    }
  }
  return submodules;
}

Future<void> main(List<String> args) async {
  final modules = await parseGitmodulesFile(
      '/Users/king/Library/Caches/OpenBranch/meta_app/ugc/.gitmodules');
  print(modules);
}
