import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:meta_tool/argument_get.dart';
import 'package:meta_tool/cache/cache_manager.dart';
import 'package:meta_tool/cache/cache_model.dart';
import 'package:meta_tool/cache/framework_aar_cache.dart';
import 'package:meta_tool/commands/build/aar/unity_aar_command.dart';
import 'package:meta_tool/commands/build/framework/unity_framework_command.dart';
import 'package:meta_tool/common.dart';
import 'package:meta_tool/define.dart';
import 'package:meta_tool/unity_environment.dart';
import 'package:path/path.dart';
import 'package:process_runner/process_runner.dart';

/// Unity强制本地编译命令 - 跳过缓存查找，直接强制本地编译，不上传网络
class UnityLocalBuildCommand extends Command {
  @override
  String get description => '跳过缓存查找，直接强制本地编译Unity，不上传网络，仅用于本地测试';

  @override
  String get name => 'unity_local';

  UnityLocalBuildCommand() {
    argParser.addOption(
      'buildPlatform',
      help: '构建平台',
      allowed: BuildPlatform.values.map((e) => e.name),
    );
    argParser.addOption(
      'buildType',
      help: '构建类型',
      allowed: BuildType.values.map((e) => e.name),
    );
    argParser.addOption(
      'unityBranch',
      help: 'Unity分支名称',
    );
    argParser.addOption(
      'buildId',
      help: '构建ID',
    );
  }

  @override
  Future<void> run() async {
    loggerInfo('🚀 开始强制本地编译Unity...');
    loggerInfo('📝 注意：此命令跳过缓存查找，直接编译，不会上传到网络');

    // 获取用户选择的参数
    final buildPlatform = ArgumentGet(argResults).getString(
      'buildPlatform',
      '请选择构建平台',
      allowed: BuildPlatform.values.map((e) => e.name).toList(),
    );

    final buildType = ArgumentGet(argResults).getString(
      'buildType',
      '请选择构建类型',
      allowed: BuildType.values.map((e) => e.name).toList(),
    );

    // 获取Unity分支列表并让用户选择
    final unityEnvironment = UnityEnvironment.fromEnvironment(appHomeDir);
    final platform = BuildPlatform.values.firstWhere(
      (e) => e.name == buildPlatform,
    );
    final unityProjectDir = Directory(
      switch (platform) {
        BuildPlatform.ios => unityEnvironment.iosUnityWorkspace,
        BuildPlatform.android => unityEnvironment.androidUnityWorkspace,
        BuildPlatform.ohos => unityEnvironment.ohosUnityWorkspace,
      },
    );

    if (!unityProjectDir.existsSync()) {
      throw Exception('Unity项目目录不存在: ${unityProjectDir.path}');
    }

    final unityBranchs = await getLatestBranchList(unityProjectDir.path).then(
      (e) => e.map((e) => getBranchName(e)).toList(),
    );

    final unityBranch = ArgumentGet(argResults).getString(
      'unityBranch',
      '请选择Unity分支',
      allowed: unityBranchs,
    );

    // 构建ID是可选的，如果用户没有指定则跳过
    final buildId = argResults?['buildId'] as String?;

    loggerInfo('🔧 构建平台: $buildPlatform');
    loggerInfo('🔧 构建类型: $buildType');
    loggerInfo('🔧 Unity分支: $unityBranch');
    if (buildId != null && buildId.isNotEmpty) {
      loggerInfo('🔧 构建ID: $buildId');
    } else {
      loggerInfo('🔧 构建ID: 未指定（将使用默认值）');
    }

    try {
      // 先导出Unity Library
      loggerInfo('📦 开始导出Unity Library...');
      await _exportUnityLibrary(buildPlatform, unityBranch, buildId);

      // 根据平台和类型调用相应的编译命令
      if (buildPlatform == BuildPlatform.android.name) {
        if (buildType == BuildType.aar.name) {
          loggerInfo('📦 开始强制编译Unity AAR...');
          await _forceCompileUnityAar(unityBranch, buildId ?? '');
        } else {
          throw Exception('Android平台只支持AAR构建类型');
        }
      } else if (buildPlatform == BuildPlatform.ios.name) {
        if (buildType == BuildType.framework.name) {
          loggerInfo('📦 开始强制编译Unity Framework...');
          await _forceCompileUnityFramework(unityBranch, buildId ?? '');
        } else {
          throw Exception('iOS平台只支持Framework构建类型');
        }
      }

      loggerSuccess('✅ Unity强制本地编译完成！');

      if (buildPlatform == BuildPlatform.android.name) {
        loggerInfo(
            '📁 AAR输出目录: ${appHomeDir.workspace}/build/unityLibrary/outputs/aar');
      } else if (buildPlatform == BuildPlatform.ios.name) {
        loggerInfo(
            '📁 Framework输出目录: ${appHomeDir.iosDir.path}/UnityLibrary/build/Release-iphoneos');
      }
    } catch (e) {
      loggerError('❌ Unity强制本地编译失败: $e');
      rethrow;
    }
  }

  /// 导出Unity Library - 调用Unity引擎导出Unity Library
  Future<void> _exportUnityLibrary(
      String buildPlatform, String unityBranch, String? buildId) async {
    // 构建Unity缓存导出命令
    final commandArgs = [
      'metax',
      'build',
      'unity_cache',
      buildPlatform,
      '--unityBranch',
      unityBranch,
      '--no-isUpload',
      '--forceUpdate',
    ];

    // 如果指定了构建ID，则添加到命令参数中
    if (buildId != null && buildId.isNotEmpty) {
      commandArgs.addAll(['--buildId', buildId]);
    }

    await ProcessRunner().runProcess(
      commandArgs,
      workingDirectory: appHomeDir.directory,
      printOutput: true,
    );
  }

  /// 强制编译Unity AAR - 跳过缓存查找，直接编译并保存到缓存目录
  Future<void> _forceCompileUnityAar(String branch, String buildId) async {
    // 直接调用Unity AAR构建逻辑，跳过缓存查找
    final unityAarCommand = UnityAarCommand();

    // 直接调用buildCache方法，跳过缓存查找和上传
    await unityAarCommand.buildCache();

    // 手动保存到缓存目录（模拟updateCache的writeToCacheSystem部分）
    await _saveAarToCache(branch, buildId);
  }

  /// 强制编译Unity Framework - 跳过缓存查找，直接编译
  Future<void> _forceCompileUnityFramework(
      String branch, String buildId) async {
    // 直接调用Unity Framework构建逻辑，跳过缓存查找
    final unityFrameworkCommand = UnityFrameworkCommand();

    // 直接调用buildCache方法，跳过缓存查找和上传
    await unityFrameworkCommand.buildCache();
  }

  /// 保存AAR到缓存目录
  Future<void> _saveAarToCache(String branch, String buildId) async {
    loggerInfo('📦 正在保存AAR到缓存目录...');

    // 获取真实的Git commitHash和commitTime
    final unityEnvironment = UnityEnvironment.fromEnvironment(appHomeDir);
    final unityProjectDir = Directory(unityEnvironment.androidUnityWorkspace);

    if (!unityProjectDir.existsSync()) {
      throw Exception('Unity项目目录不存在: ${unityProjectDir.path}');
    }

    final commitHash = await getCurrentCommitHash(unityProjectDir.path);
    final commitTime = await getCommitTime(unityProjectDir.path, commitHash);

    // 构建缓存目录路径
    final buildCacheDir = join(
      appHomeDir.workspace,
      'build',
      'unityLibrary',
      'outputs',
      'aar',
    );

    // 创建AarCache实例
    final unityCache = AarCache(
      branch: branch,
      buildConfiguration: BuildConfiguration.release,
      buildLibrary: BuildLibrary.unity,
      buildId: buildId.isNotEmpty ? int.parse(buildId) : 0,
    );

    // 写入构建缓存信息
    await BuildCacheManager(buildCacheDir).write([
      CacheModel(
        buildPlatform: BuildPlatform.android.value,
        buildLibrary: BuildLibrary.unity.value,
        buildType: BuildType.aar.value,
        branch: branch,
        configuration: BuildConfiguration.release.value,
        commitHash: commitHash,
        buildId: buildId.isNotEmpty ? buildId : '0',
        commitTime: commitTime,
      ),
    ]);

    // 压缩并保存到缓存系统
    final buildCacheParentDir = Directory(buildCacheDir).parent;
    final zipFile = File(join(buildCacheParentDir.path, '$commitHash.zip'));

    // 压缩AAR目录
    await ProcessRunner().runProcess(
      [
        'zip',
        "-r",
        zipFile.path,
        './',
      ],
      workingDirectory: Directory(buildCacheDir),
      printOutput: true,
    );

    // 保存到缓存系统
    await unityCache.updateCacheData(
      zipFile,
      CacheModel(
        branch: branch,
        commitHash: commitHash,
        buildId: buildId.isNotEmpty ? buildId : '0',
        configuration: BuildConfiguration.release.value,
        buildPlatform: BuildPlatform.android.value,
        buildLibrary: BuildLibrary.unity.value,
        buildType: BuildType.aar.value,
        commitTime: commitTime,
      ),
    );

    // 清理临时zip文件
    await zipFile.delete();

    loggerSuccess('✅ AAR已保存到缓存目录: ${unityCache.cacheHomeDir}');
  }
}
