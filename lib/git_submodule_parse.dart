import 'dart:convert';
import 'dart:io';

class GitSubmodule {
  String? path;
  String? url;
  String? name;
  String? branch;

  @override
  String toString() => '''
name = $name
path = $path
url = $url
branch = $branch
''';
}

Future<List<GitSubmodule>> parseGitmodulesFile(String filePath) async {
  final file = File(filePath);
  if (!await file.exists()) {
    throw Exception('Gitmodules file not found: $filePath');
  }

  final content = await file.readAsString();
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
