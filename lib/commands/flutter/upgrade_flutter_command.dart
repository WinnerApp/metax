import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:meta_tool/cache/cache_manager.dart';
import 'package:meta_tool/common.dart';
import 'package:meta_tool/define.dart';
import 'package:meta_tool/flutter_sdk.dart';
import 'package:path/path.dart';
import 'package:process_runner/process_runner.dart';

/// 打包机 Flutter 升级后处理（不含 fvm install，需自行先装好对应版本）。
///
/// 示例:
///   fvm install 3.41.9   # 自行安装
///   metax flutter upgrade --version 3.41.9
///   metax flutter upgrade 3.41.9 --platform all
///   metax --workspace /path/to/app flutter upgrade --version 3.41.9
///   metax flutter upgrade --version 3.41.9 --project /path/to/metaapp_flutter
class UpgradeFlutterCommand extends Command {
  @override
  String get description =>
      'FVM 安装完成后的打包机处理：切换版本、预下载引擎、清理旧产物缓存（不执行 fvm install）';

  @override
  String get name => 'upgrade';

  late ProcessRunner _runner;

  /// 官方 Flutter git；升级后处理时忽略环境里的中国区镜像变量
  static const _officialFlutterGitUrl =
      'https://github.com/flutter/flutter.git';

  UpgradeFlutterCommand() {
    argParser.addOption(
      'version',
      abbr: 'v',
      help: '目标 Flutter 版本（须已通过 fvm install 安装），如 3.41.9；也可作为位置参数传入',
    );
    argParser.addOption(
      'project',
      abbr: 'p',
      help: 'Flutter 模块工程目录；默认使用 --workspace 下的 metaapp_flutter',
    );
    argParser.addOption(
      'platform',
      help: '预下载与清理的目标平台',
      allowed: ['all', 'ios', 'android'],
      defaultsTo: 'all',
    );
    argParser.addFlag(
      'skip-precache',
      help: '跳过 flutter precache',
      defaultsTo: false,
      negatable: false,
    );
    argParser.addFlag(
      'metax-clean',
      help: '清理 ~/.metax 下对应平台的 flutter 缓存',
      defaultsTo: true,
    );
    argParser.addFlag(
      'set-global',
      help: '执行 fvm global 设置全局默认版本',
      defaultsTo: true,
    );
    argParser.addFlag(
      'use-china-mirror',
      help: '使用国内镜像（默认关闭，走官方源；可通过代理访问）',
      defaultsTo: false,
      negatable: false,
    );
  }

  @override
  Future<void> run() async {
    final version = _resolveVersion();
    final platform = argResults!['platform'] as String;
    final skipPrecache = argResults!['skip-precache'] as bool;
    final cleanMetax = argResults!['metax-clean'] as bool;
    final setGlobal = argResults!['set-global'] as bool;
    final useChinaMirror = argResults!['use-china-mirror'] as bool;
    final needIos = platform == 'all' || platform == 'ios';
    final needAndroid = platform == 'all' || platform == 'android';

    _runner = ProcessRunner(
      environment: _buildProcessEnvironment(useChinaMirror),
      // 必须 false：否则父进程里残留的中国区镜像变量仍会生效
      includeParentEnvironment: false,
    );

    final projectDir = _resolveProjectDir();

    loggerInfo('目标 Flutter 版本: $version');
    loggerInfo('目标平台: $platform');
    loggerInfo(
      useChinaMirror
          ? '源站: 国内镜像'
          : '源站: Flutter 官方（忽略中国区 FLUTTER_STORAGE / PUB_HOSTED / FVM_FLUTTER_URL）',
    );
    _logProxyStatus();
    if (projectDir != null) {
      loggerInfo('Flutter 工程: ${projectDir.path}');
    } else {
      loggerWarning('未指定工程目录，将跳过工程内 fvm use / flutter clean');
    }

    await _ensureFvmAvailable();
    await _ensureFvmVersionInstalled(version);

    if (setGlobal) {
      try {
        loggerInfo('设置 fvm global -> $version');
        await _run(['fvm', 'global', version]);
      } catch (e) {
        loggerWarning('fvm global 失败，可忽略（部分 FVM 版本不支持）: $e');
      }
    }

    if (projectDir != null) {
      loggerInfo('在工程内切换版本: ${projectDir.path}');
      await _run(
        ['fvm', 'use', version, '--force'],
        workingDirectory: projectDir,
      );
    }

    final flutterCommand = projectDir != null
        ? <String>['fvm', 'flutter']
        : await _globalFlutterCommand();

    if (!skipPrecache) {
      if (needIos) {
        loggerInfo('预下载 iOS 引擎 (flutter precache --ios) ...');
        await _run(
          [...flutterCommand, 'precache', '--ios'],
          workingDirectory: projectDir,
        );
      }
      if (needAndroid) {
        loggerInfo('预下载 Android 引擎 (flutter precache --android) ...');
        await _run(
          [...flutterCommand, 'precache', '--android'],
          workingDirectory: projectDir,
        );
      }
    } else {
      loggerWarning('已跳过 precache');
    }

    final sdk = await _resolveSdkInfo(flutterCommand, projectDir);
    loggerInfo('flutterVersion     = ${sdk.version}');
    loggerInfo('frameworkRevision  = ${sdk.frameworkRevision}');
    loggerInfo('engineRevision     = ${sdk.engineRevision}');
    loggerInfo('flutterRoot        = ${sdk.flutterRoot}');

    if (sdk.version != version && !sdk.version.startsWith(version)) {
      loggerWarning('实际版本 (${sdk.version}) 与目标 ($version) 不一致，请检查 FVM 配置');
    }
    await _verifyEngineFile(sdk);

    if (projectDir != null) {
      await _cleanProjectCaches(
        projectDir: projectDir,
        flutterCommand: flutterCommand,
        needIos: needIos,
        needAndroid: needAndroid,
      );
    }

    if (cleanMetax) {
      await _cleanMetaxFlutterCaches(platform);
    } else {
      loggerWarning('已跳过 metax 清理 (--no-metax-clean)');
    }

    loggerInfo('当前已安装 FVM 版本:');
    try {
      await _run(['fvm', 'list']);
    } catch (_) {}

    loggerInfo('运行 flutter doctor -v（仅诊断）...');
    try {
      await _run(
        [...flutterCommand, 'doctor', '-v'],
        workingDirectory: projectDir,
      );
    } catch (_) {}

    _printNextSteps(version, platform, needIos, needAndroid, sdk);
    loggerSuccess(
      'Flutter 升级完成: ${sdk.version}@${sdk.engineRevision} (platform=$platform)',
    );
  }

  String _resolveVersion() {
    final option = argResults!['version'] as String?;
    if (option != null && option.trim().isNotEmpty) {
      return option.trim();
    }
    final rest = argResults!.rest;
    if (rest.isNotEmpty && rest.first.trim().isNotEmpty) {
      return rest.first.trim();
    }
    throw UsageException(
      '必须指定 Flutter 版本，例如: metax flutter upgrade --version 3.41.9',
      usage,
    );
  }

  Directory? _resolveProjectDir() {
    final projectOption = argResults!['project'] as String?;
    if (projectOption != null && projectOption.trim().isNotEmpty) {
      final dir = Directory(projectOption.trim());
      _assertFlutterProject(dir);
      return dir;
    }
    try {
      final flutterDir = appHomeDir.flutterDir;
      if (File(join(flutterDir.path, 'pubspec.yaml')).existsSync()) {
        return flutterDir;
      }
    } catch (_) {
      // appHomeDir 未初始化时忽略
    }
    return null;
  }

  void _assertFlutterProject(Directory dir) {
    if (!File(join(dir.path, 'pubspec.yaml')).existsSync()) {
      throw Exception('${dir.path} 不是 Flutter 工程（缺少 pubspec.yaml）');
    }
  }

  Future<void> _ensureFvmAvailable() async {
    try {
      final result = await _runner.runProcess(
        ['which', 'fvm'],
        printOutput: false,
      );
      if (result.stdout.trim().isEmpty) {
        throw Exception('未找到 fvm');
      }
    } catch (_) {
      throw Exception('未找到 fvm，请先安装: dart pub global activate fvm');
    }
  }

  Future<List<String>> _globalFlutterCommand() async {
    // 无工程时尽量走 fvm flutter，保证用到刚 install 的版本
    return <String>['fvm', 'flutter'];
  }

  /// 默认走官方源：清掉中国区镜像变量，保留代理；可选开启国内镜像。
  Map<String, String> _buildProcessEnvironment(bool useChinaMirror) {
    final env = Map<String, String>.from(Platform.environment);
    if (useChinaMirror) {
      env['PUB_HOSTED_URL'] = 'https://pub.flutter-io.cn';
      env['FLUTTER_STORAGE_BASE_URL'] = 'https://storage.flutter-io.cn';
      env['FVM_FLUTTER_URL'] =
          'https://mirrors.tuna.tsinghua.edu.cn/git/flutter-sdk.git';
      env['FLUTTER_GIT_URL'] = env['FVM_FLUTTER_URL']!;
      return env;
    }

    // 忽略中国区 / 自定义镜像，强制官方
    for (final key in [
      'PUB_HOSTED_URL',
      'FLUTTER_STORAGE_BASE_URL',
      'FVM_FLUTTER_URL',
      'FLUTTER_GIT_URL',
    ]) {
      env.remove(key);
    }
    env['FVM_FLUTTER_URL'] = _officialFlutterGitUrl;
    env['FLUTTER_GIT_URL'] = _officialFlutterGitUrl;
    return env;
  }

  void _logProxyStatus() {
    final env = Platform.environment;
    final keys = ['https_proxy', 'http_proxy', 'all_proxy', 'HTTPS_PROXY', 'HTTP_PROXY', 'ALL_PROXY'];
    final found = <String>[];
    for (final key in keys) {
      final value = env[key];
      if (value != null && value.isNotEmpty) {
        found.add('$key=$value');
      }
    }
    if (found.isEmpty) {
      loggerWarning(
        '未检测到代理环境变量；若 GitHub 不稳定，请在同一 shell 先 export http(s)_proxy / all_proxy',
      );
    } else {
      loggerInfo('已检测到代理: ${found.join(', ')}');
    }
  }

  Future<void> _ensureFvmVersionInstalled(String version) async {
    final versionDir = _fvmVersionDir(version);
    final binFlutter = File(join(versionDir.path, 'bin', 'flutter'));
    if (await binFlutter.exists()) {
      loggerInfo('已检测到本机 FVM 版本: ${versionDir.path}');
      return;
    }
    throw Exception(
      '未找到 FVM 版本 $version（${versionDir.path}）。\n'
      '请先自行安装后再执行本命令:\n'
      '  fvm install $version\n'
      '  metax flutter upgrade --version $version',
    );
  }

  Directory _fvmVersionDir(String version) {
    final home = Platform.environment['HOME'] ?? '';
    final cachePath = Platform.environment['FVM_CACHE_PATH'] ??
        Platform.environment['FVM_HOME'] ??
        join(home, 'fvm');
    return Directory(join(cachePath, 'versions', version));
  }

  Future<void> _run(
    List<String> command, {
    Directory? workingDirectory,
  }) async {
    await _runner.runProcess(
      command,
      workingDirectory: workingDirectory,
      printOutput: true,
    );
  }

  Future<_SdkInfo> _resolveSdkInfo(
    List<String> flutterCommand,
    Directory? projectDir,
  ) async {
    final result = await _runner.runProcess(
      [...flutterCommand, '--version', '--machine'],
      workingDirectory: projectDir,
      printOutput: true,
    );
    final json = _parseVersionMachineJson(result.stdout);
    final version = (json['flutterVersion'] ?? json['frameworkVersion'] ?? 'unknown')
        .toString();
    final engineRevision = (json['engineRevision'] ?? '').toString();
    final frameworkRevision = (json['frameworkRevision'] ?? '').toString();
    var flutterRoot = (json['flutterRoot'] ?? '').toString().trim();
    if (flutterRoot.isEmpty || flutterRoot == '.' || flutterRoot == './') {
      flutterRoot = await _resolveFlutterRoot(flutterCommand, projectDir);
    }
    return _SdkInfo(
      version: version,
      engineRevision: engineRevision,
      frameworkRevision: frameworkRevision,
      flutterRoot: flutterRoot,
    );
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

  Future<String> _resolveFlutterRoot(
    List<String> flutterCommand,
    Directory? projectDir,
  ) async {
    try {
      final which = await _runner.runProcess(
        projectDir != null
            ? <String>['fvm', 'exec', 'which', 'flutter']
            : <String>['which', 'flutter'],
        workingDirectory: projectDir,
        printOutput: false,
      );
      final flutterBin = pickFlutterBinPath(which.stdout);
      if (flutterBin != null) {
        return File(flutterBin).parent.parent.path;
      }
    } catch (_) {}

    final doctor = await _runner.runProcess(
      [...flutterCommand, 'doctor', '-v'],
      workingDirectory: projectDir,
      printOutput: false,
    );
    for (final line in doctor.stdout.split('\n')) {
      final match = RegExp(r'at (/.*)').firstMatch(line);
      if (match != null && line.contains('Flutter version')) {
        return match.group(1)!.trim();
      }
    }
    throw Exception('无法解析 Flutter SDK 根目录');
  }

  Future<void> _verifyEngineFile(_SdkInfo sdk) async {
    final engineFile = File(join(sdk.flutterRoot, 'bin', 'internal', 'engine.version'));
    if (!await engineFile.exists()) {
      loggerWarning('未找到 engine.version: ${engineFile.path}');
      return;
    }
    final fileEngine = (await engineFile.readAsString()).trim();
    loggerInfo('engine.version 文件 = $fileEngine');
    if (sdk.engineRevision.isNotEmpty && fileEngine != sdk.engineRevision) {
      throw Exception(
        'engineRevision 与 bin/internal/engine.version 不一致，SDK 可能不完整。'
        '建议: fvm remove ${sdk.version} && fvm install ${sdk.version}',
      );
    }
  }

  Future<void> _cleanProjectCaches({
    required Directory projectDir,
    required List<String> flutterCommand,
    required bool needIos,
    required bool needAndroid,
  }) async {
    loggerWarning('清理工程内 Flutter 构建缓存 ...');
    try {
      await _run(
        [...flutterCommand, 'clean'],
        workingDirectory: projectDir,
      );
    } catch (e) {
      loggerWarning('flutter clean 失败，继续删除本地目录: $e');
    }

    await _deleteDirIfExists(Directory(join(projectDir.path, 'build')));
    await _deleteDirIfExists(Directory(join(projectDir.path, '.dart_tool')));

    if (needIos) {
      await _deleteDirIfExists(Directory(join(projectDir.path, '.ios', 'Pods')));
      await _deleteDirIfExists(
        Directory(join(projectDir.path, '.ios', '.symlinks')),
      );
      await _deleteFileIfExists(
        File(join(projectDir.path, '.ios', 'Flutter', 'Flutter.podspec')),
      );
      await _deleteFileIfExists(
        File(join(projectDir.path, '.ios', 'Podfile.lock')),
      );
    }
    if (needAndroid) {
      await _deleteDirIfExists(Directory(join(projectDir.path, '.android')));
    }
  }

  Future<void> _cleanMetaxFlutterCaches(String platform) async {
    final metaxHome = Directory(join(readEnv('HOME'), '.metax'));
    if (!await metaxHome.exists()) {
      loggerWarning('~/.metax 不存在，跳过 metax 清理');
      return;
    }

    loggerWarning('清理 ~/.metax 中的 Flutter 缓存 ...');
    await for (final platformEntity in metaxHome.list()) {
      if (platformEntity is! Directory) continue;
      final platformName = basename(platformEntity.path);
      if (platformName == 'flutter_sdk') continue;
      if (platform != 'all' && platformName != platform) continue;

      await for (final configEntity in platformEntity.list()) {
        if (configEntity is! Directory) continue;
        final configName = basename(configEntity.path);
        if (configName != 'debug' && configName != 'release') continue;
        final flutterDir = Directory(join(configEntity.path, 'flutter'));
        if (await flutterDir.exists()) {
          await flutterDir.delete(recursive: true);
          loggerDebug('已删除: ${flutterDir.path}');
        }
      }
    }

    final fingerprintDir = Directory(join(metaxHome.path, 'flutter_sdk'));
    if (await fingerprintDir.exists()) {
      await fingerprintDir.delete(recursive: true);
      loggerDebug('已清除 Flutter SDK 指纹目录: ${fingerprintDir.path}');
    }

    final manager = MetaxCacheManager();
    final allModels = await manager.read();
    final filtered = allModels.where((model) {
      if (model.buildLibrary != 'flutter') return true;
      if (platform == 'all') return false;
      return model.buildPlatform != platform;
    }).toList();
    if (filtered.length != allModels.length) {
      await manager.write(filtered);
      loggerDebug(
        '已从 ~/.metax/cache.json 移除 ${allModels.length - filtered.length} 条 flutter 索引',
      );
    }
  }

  Future<void> _deleteDirIfExists(Directory dir) async {
    if (await dir.exists()) {
      await dir.delete(recursive: true);
      loggerDebug('已删除目录: ${dir.path}');
    }
  }

  Future<void> _deleteFileIfExists(File file) async {
    if (await file.exists()) {
      await file.delete();
      loggerDebug('已删除文件: ${file.path}');
    }
  }

  void _printNextSteps(
    String version,
    String platform,
    bool needIos,
    bool needAndroid,
    _SdkInfo sdk,
  ) {
    final buffer = StringBuffer()
      ..writeln()
      ..writeln('下一步（打包机务必做）:')
      ..writeln('  1. 确认业务仓 .fvmrc / .fvm/fvm_config.json 已是 $version，并已提交')
      ..writeln('  2. 用 metax 强制重打 Flutter 产物（不要复用旧远程缓存）:');
    if (needIos) {
      buffer
        ..writeln('  [iOS]')
        ..writeln('    metax build framework flutter -c release --forceUpdate')
        ..writeln(
          '    metax flutter verify <产物目录>  # 校验 Framework 与 engine 是否一致',
        )
        ..writeln('    # 宿主重新集成 frameworks/flutter 后再打 IPA');
    }
    if (needAndroid) {
      buffer
        ..writeln('  [Android]')
        ..writeln('    metax build aar flutter -c release --forceUpdate')
        ..writeln('    # 宿主重新集成 aar/flutter 后再打 APK/AAB');
    }
    buffer
      ..writeln('  [鸿蒙]')
      ..writeln('    metax build har flutter -c release --forceUpdate')
      ..writeln('    # 宿主重新集成 ohos/aar/flutter/release 后再打 .app');
    buffer
      ..writeln('     也可临时关闭 Flutter 缓存: metax ... --no-isUseCache')
      ..writeln()
      ..writeln('当前指纹（可与报错里的 engine 对照）:')
      ..writeln('  version@engine = ${sdk.version}@${sdk.engineRevision}');
    loggerInfo(buffer.toString());
  }
}

class _SdkInfo {
  final String version;
  final String engineRevision;
  final String frameworkRevision;
  final String flutterRoot;

  const _SdkInfo({
    required this.version,
    required this.engineRevision,
    required this.frameworkRevision,
    required this.flutterRoot,
  });
}
