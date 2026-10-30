import 'dart:io';

import 'package:meta_tool/app_home_dir.dart';
import 'package:meta_tool/common.dart';
import 'package:path/path.dart';
import 'package:process_runner/process_runner.dart';

/// 鸿蒙 Unity WebGL：把 `ohos/unityWebgl/assets` sync 到
/// `ohos/entry/src/main/resources/rawfile/unity_webgl`（注入 jsbridge + 版本戳）。
///
/// 缓存 zip 只落在 assets；rawfile 是打包/运行时目录，必须额外 sync。
Future<void> syncOhosUnityWebglToRawfile(AppHomeDir appHomeDir) async {
  final assetsDir = Directory(
    join(appHomeDir.ohosDir.path, 'unityWebgl', 'assets'),
  );
  final scriptFile = File(
    join(
      appHomeDir.ohosDir.path,
      'unityWebgl',
      'scripts',
      'sync_webgl_assets.sh',
    ),
  );
  final rawfileDir = Directory(
    join(
      appHomeDir.ohosDir.path,
      'entry',
      'src',
      'main',
      'resources',
      'rawfile',
      'unity_webgl',
    ),
  );

  if (!assetsDir.existsSync()) {
    throw Exception(
      '鸿蒙 WebGL assets 不存在: ${assetsDir.path}，请先执行 '
      'metax build unity_cache ohos 或 metax cache use-local-cache',
    );
  }
  if (!File(join(assetsDir.path, 'index.html')).existsSync()) {
    throw Exception(
      '鸿蒙 WebGL assets 缺少 index.html: ${assetsDir.path}',
    );
  }
  if (!scriptFile.existsSync()) {
    throw Exception(
      '找不到 sync 脚本: ${scriptFile.path}',
    );
  }

  // 确保可执行（从 git 检出时偶发丢 +x）
  await ProcessRunner().runProcess(
    ['chmod', '+x', scriptFile.path],
    printOutput: false,
  );

  loggerInfo(
    '🔄 sync WebGL assets → rawfile\n'
    '   assets:  ${assetsDir.path}\n'
    '   rawfile: ${rawfileDir.path}',
  );
  await ProcessRunner().runProcess(
    [scriptFile.path, assetsDir.path],
    printOutput: true,
  );
  loggerSuccess('鸿蒙 WebGL rawfile 同步完成: ${rawfileDir.path}');
}
