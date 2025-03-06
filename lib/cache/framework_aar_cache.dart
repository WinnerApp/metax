import 'dart:io';

import 'package:darty_json_safe/darty_json_safe.dart';
import 'package:meta_tool/cache/cache.dart';
import 'package:path/path.dart';

class FrameworkAarCache extends Cache {
  final FrameworkAarPlatform platform;
  final FrameworkAarType type;

  FrameworkAarCache({required this.platform, required this.type});
 

  @override
  String get cacheHome => join(super.cacheHome, type.value, platform.value);
  
  @override
  Future<String?> getBranchLatestCommitHash(String branch) async {
    final ids = await getIdsFromBranch(branch);
    return ids.isEmpty ? null : ids.last;
  }

  @override
  Map<String, dynamic> updateCacheData(
      Map<String, dynamic> cacheData, String branch, String commitHash) {
    List<String> ids = [
      ...JSON(cacheData)[branch].listValue.map((e) => e.toString())
    ];
    ids.add(commitHash);
    cacheData[branch] = ids;
    return cacheData;
  }

  @override
  Future<void> updateBranchLatestCommitHash(
      String branch, String commitHash, File zipFile) async {
    final cacheZipPath = getCommitHashCachePath(commitHash);
    if (!await File(cacheZipPath).exists()) {
      await zipFile.copy(cacheZipPath);
    }
    List<String> ids = [...await getIdsFromBranch(branch)];
    ids.add(commitHash);
    final jsonText =
        await File(cacheJsonPath).readAsString().catchError((e) => '{}');
    final json = JSON(jsonText);
    json[branch] = ids;
    if (!await File(cacheJsonPath).exists()) {
      await File(cacheJsonPath).create(recursive: true);
    }
    await File(cacheJsonPath).writeAsString(json.stringValue);
  }

  Future<List<String>> getIdsFromBranch(String branch) async {
    final json = JSON(await getCacheData(branch));
    return json[branch].listValue.map((e) => e.toString()).toList();
  }
}

enum FrameworkAarPlatform {
  flutter('flutter'),
  unity('unity');

  final String value;
  const FrameworkAarPlatform(this.value);
}

enum FrameworkAarType {
  framework('framework'),
  aar('aar');

  final String value;

  const FrameworkAarType(this.value);
}
