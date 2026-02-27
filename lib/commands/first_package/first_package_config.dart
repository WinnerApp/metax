import 'dart:io';

import 'package:args/args.dart';
import 'package:meta_tool/common.dart';
import 'package:path/path.dart';

Directory _getFirstPackageCacheDir() {
  // macOS: ~/Library/Caches/metax/first_package
  if (Platform.isMacOS) {
    final home = readEnv('HOME');
    return Directory(
      join(
        home,
        'Library',
        'Caches',
        'metax',
        'first_package',
      ),
    );
  }

  // Windows: %LOCALAPPDATA%/metax/first_package
  if (Platform.isWindows) {
    final localAppData = readEnv('LOCALAPPDATA');
    return Directory(
      join(
        localAppData,
        'metax',
        'first_package',
      ),
    );
  }

  // 其他平台：~/.cache/metax/first_package
  final home = readEnv('HOME');
  return Directory(
    join(
      home,
      '.cache',
      'metax',
      'first_package',
    ),
  );
}

File getFirstPackageConfigFile() {
  final cacheDir = _getFirstPackageCacheDir();
  return File(join(cacheDir.path, 'first_package_cache.env'));
}

/// 确保首包缓存目录的配置文件存在
/// - 如果存在：打印配置内容并返回环境 Map
/// - 如果不存在：提示用户通过初始化命令进行配置
Future<Map<String, String>> ensureFirstPackageCacheConfig(
  ArgResults? argResults,
) async {
  final configFile = getFirstPackageConfigFile();

  if (await configFile.exists()) {
    loggerInfo('检测到首包缓存配置文件: ${configFile.path}');
    final environment = readEnvironmentFromFile(configFile.path);
    if (environment.isEmpty) {
      loggerWarning('配置文件内容为空，请重新初始化首包配置。');
    } else {
      loggerInfo('当前配置如下:');
      environment.forEach((key, value) {
        loggerInfo('$key=$value');
      });
      return environment;
    }
  }

  throw '首包配置未初始化，请先执行 `metax first_package init` 初始化首包参数';
}
