import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:meta_tool/app_home_dir.dart';
import 'package:meta_tool/appwrite_environment.dart';
import 'package:meta_tool/appwrite_server.dart';
import 'package:meta_tool/argument_get.dart';
import 'package:meta_tool/cache/cache_cleaner.dart';
import 'package:meta_tool/cache/cache_manager.dart';
import 'package:meta_tool/cache/cache_model.dart';
import 'package:meta_tool/cache/metax_cache.dart';
import 'package:meta_tool/common.dart';
import 'package:meta_tool/define.dart';
import 'package:meta_tool/unity_environment.dart';
import 'package:path/path.dart';
import 'package:process_runner/process_runner.dart';

class UseCacheCommand extends Command {
  @override
  String get description => '使用缓存,缓存顺序本地缓存->网络缓存->本地编译缓存';

  @override
  String get name => 'use';

  UseCacheCommand() {
    argParser.addOption(
      'buildPlatform',
      help: '构建平台',
      allowed: BuildPlatform.values.map((e) => e.name),
    );
    argParser.addOption(
      'buildConfiguration',
      help: '构建配置',
      allowed: BuildConfiguration.values.map((e) => e.name),
    );

    argParser.addOption(
      'buildLibrary',
      help: '构建库',
      allowed: BuildLibrary.values.map((e) => e.name),
    );
    argParser.addOption(
      'buildType',
      help: '构建类型',
      allowed: BuildType.values.map((e) => e.name),
    );
    argParser.addOption('branch', help: '分支');
    argParser.addOption('commitHash', help: 'Git Hash');
    argParser.addOption('buildId', help: '构建ID');
    argParser.addOption('unityBranch', help: 'Unity分支');
    argParser.addFlag(
      'isUpload',
      help: '是否上传网络缓存',
      defaultsTo: true,
    );
  }

  late String buildPlatform;
  late String buildLibrary;
  late String buildConfiguration;
  late String buildType;
  late String branch;
  late AppwriteCacheEnvironment appwriteCacheEnvironment;
  late String? commitHash;
  late String? buildId;
  late bool isUpload;
  @override
  Future<void> run() async {
    appwriteCacheEnvironment = AppwriteCacheEnvironment(appHomeDir);
    buildPlatform = ArgumentGet(argResults).getString(
      'buildPlatform',
      '请选择构建平台',
      allowed: BuildPlatform.values.map((e) => e.name).toList(),
    );
    if (buildPlatform == BuildPlatform.ios.name &&
        !appHomeDir.iosDir.existsSync()) {
      throw Exception('目录[${appHomeDir.iosDir.path}]不存在,无法初始化缓存！');
    }
    if (buildPlatform == BuildPlatform.android.name &&
        !appHomeDir.androidDir.existsSync()) {
      throw Exception('目录[${appHomeDir.androidDir.path}]不存在,无法初始化缓存！');
    }
    if (buildPlatform == BuildPlatform.ohos.name &&
        !appHomeDir.ohosDir.existsSync()) {
      throw Exception('目录[${appHomeDir.ohosDir.path}]不存在,无法初始化缓存！');
    }

    buildLibrary = ArgumentGet(argResults).getString(
      'buildLibrary',
      '请选择构建库',
      allowed: BuildLibrary.values.map((e) => e.name).toList(),
    );
    if (buildLibrary == BuildLibrary.flutter.name) {
      buildConfiguration = ArgumentGet(argResults).getString(
        'buildConfiguration',
        '请选择构建配置',
        allowed: BuildConfiguration.values.map((e) => e.name).toList(),
      );
    } else {
      buildConfiguration = BuildConfiguration.release.name;
    }

    if (buildPlatform == BuildPlatform.ios.name) {
      if (buildLibrary == BuildLibrary.flutter.name) {
        buildType = BuildType.framework.value;
      } else {
        buildType = ArgumentGet(argResults).getString(
          'buildType',
          '请选择构建类型',
          allowed: [
            BuildType.framework.value,
            BuildType.library.value,
          ],
        );
      }
    } else if (buildPlatform == BuildPlatform.ohos.name) {
      if (buildLibrary == BuildLibrary.flutter.name) {
        buildType = BuildType.har.value;
      } else {
        buildType = ArgumentGet(argResults).getString(
          'buildType',
          '请选择构建类型',
          allowed: [
            BuildType.har.value,
            BuildType.library.value,
          ],
        );
      }
    } else {
      if (buildLibrary == BuildLibrary.flutter.name) {
        buildType = BuildType.aar.value;
      } else {
        buildType = ArgumentGet(argResults).getString(
          'buildType',
          '请选择构建类型',
          allowed: [
            BuildType.aar.value,
            BuildType.library.value,
          ],
        );
      }
    }

    if (buildLibrary == BuildLibrary.unity.name) {
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

      /// 如果开启skipGitPull，则跳过Git操作，直接使用本地代码
      if (skipGitPull) {
        loggerInfo('跳过Git操作模式，使用本地代码');
        branch = ArgumentGet(argResults).getString(
          'unityBranch',
          '请输入Unity分支',
        );
      } else {
        final branchs = await getLatestBranchList(unityProjectDir.path).then(
          (e) => e.map((e) => getBranchName(e)).toList(),
        );
        branch = ArgumentGet(argResults).getString(
          'unityBranch',
          '请输入Unity分支',
          allowed: branchs,
        );
      }
    } else if (buildLibrary == BuildLibrary.flutter.name) {
      /// 如果开启skipGitPull，则跳过Git操作，直接使用本地代码
      if (skipGitPull) {
        loggerInfo('跳过Git操作模式，使用本地代码');
        branch = ArgumentGet(argResults).getString(
          'branch',
          '请输入分支',
        );
      } else {
        final flutterBranchs =
            await getLatestBranchList(appHomeDir.flutterDir.path).then(
          (e) => e.map((e) => getBranchName(e)).toList(),
        );
        loggerDebug('flutterBranchs: $flutterBranchs');
        branch = ArgumentGet(argResults).getString(
          'branch',
          '请输入分支',
          allowed: flutterBranchs,
        );
      }
    }

    commitHash = argResults?['commitHash'] as String?;
    buildId = argResults?['buildId'] as String?;
    isUpload = argResults?['isUpload'] ?? true;

    CacheModel? useCacheModel;
    final library = BuildLibrary.values.firstWhere((e) => e.name == buildLibrary);
    final enableLibraryCache = isLibraryCacheEnabled(library);
    if (enableLibraryCache) {
      loggerDebug('正在查询本地缓存...');
      final localCacheModel = await queryLocalCache();
      if (localCacheModel != null) {
        loggerDebug('查询到本地缓存: ${localCacheModel.commitHash}');
        useCacheModel = localCacheModel;
      } else {
        loggerDebug('本地缓存不存在,正在查询网络缓存...');
        final networkCacheModel = await queryNetworkCache();
        if (networkCacheModel != null) {
          loggerDebug('查询到网络缓存: ${networkCacheModel.commitHash}');
          useCacheModel = networkCacheModel;

          /// 下载网络缓存
          await downloadCacheResource(
            workspace: appHomeDir.workspace,
            buildPlatform: BuildPlatform.values.firstWhere(
              (e) => e.name == buildPlatform,
            ),
            buildLibrary: BuildLibrary.values.firstWhere(
              (e) => e.name == buildLibrary,
            ),
            buildConfiguration: BuildConfiguration.values.firstWhere(
              (e) => e.name == buildConfiguration,
            ),
            buildType: BuildType.values.firstWhere(
              (e) => e.name == buildType,
            ),
            branch: branch,
            commitHash: networkCacheModel.commitHash,
            buildId: int.parse(networkCacheModel.buildId),
          );
        }
      }
    } else {
      await cleanCachesOnIgnore(
        appHomeDir: appHomeDir,
        library: library,
      );
    }
    useCacheModel ??= await compileCache();
    if (useCacheModel == null) {
      throw Exception('无法找到对应缓存!');
    }
    await useCache(useCacheModel);
    loggerSuccess('使用缓存成功');
  }

  /// 查询本地是否存在缓存
  Future<CacheModel?> queryLocalCache() async {
    final metaxCacheManager = MetaxCacheManager();
    final localCacheModels = await metaxCacheManager.read();

    /// 获取当前分支的最新缓存
    final cacheModel = findCacheInList(localCacheModels);
    if (cacheModel == null) return null;
    loggerDebug('查询到本地缓存: ${cacheModel.commitHash}');
    final metaxCache = createMetaxCache(int.parse(cacheModel.buildId));
    if (!await metaxCache.isCacheExists(cacheModel.commitHash)) return null;
    return cacheModel;
  }

  /// 根据buildId创建MetaxCache
  MetaxCache createMetaxCache(int buildId) {
    return MetaxCache(
      buildPlatform: BuildPlatform.values.firstWhere(
        (e) => e.name == buildPlatform,
      ),
      buildConfiguration: BuildConfiguration.values.firstWhere(
        (e) => e.name == buildConfiguration,
      ),
      buildLibrary: BuildLibrary.values.firstWhere(
        (e) => e.name == buildLibrary,
      ),
      buildType: BuildType.values.firstWhere(
        (e) => e.name == buildType,
      ),
      branch: branch,
      buildId: buildId,
    );
  }

  /// 获取二进制缓存存放的路径
  String getBinaryCachePath({
    required AppHomeDir appHomeDir,
    required String buildPlatform,
    required String buildLibrary,
    required String buildType,
    required String buildConfiguration,
  }) {
    if (buildPlatform == BuildPlatform.ios.name) {
      if (buildType == BuildType.library.name) {
        return join(appHomeDir.iosDir.path, 'UnityLibrary');
      } else if (buildType == BuildType.framework.name) {
        if (buildLibrary == BuildLibrary.unity.name) {
          return join(appHomeDir.iosDir.path, 'frameworks', 'unity');
        } else if (buildLibrary == BuildLibrary.flutter.name) {
          if (buildConfiguration == BuildConfiguration.release.name) {
            return join(
                appHomeDir.iosDir.path, 'frameworks', 'flutter', 'Release');
          } else if (buildConfiguration == BuildConfiguration.debug.name) {
            return join(
                appHomeDir.iosDir.path, 'frameworks', 'flutter', 'Debug');
          } else {
            throw Exception('不支持的构建配置: $buildConfiguration');
          }
        } else {
          throw Exception('不支持的构建库: $buildLibrary');
        }
      } else {
        throw Exception('不支持的构建类型: $buildType');
      }
    } else if (buildPlatform == BuildPlatform.android.name) {
      if (buildType == BuildType.library.name) {
        return join(appHomeDir.unityAndroidDir.path, 'unityLibrary');
      } else if (buildType == BuildType.aar.name) {
        if (buildLibrary == BuildLibrary.unity.name) {
          return join(appHomeDir.androidDir.path, 'aar', 'unity');
        } else if (buildLibrary == BuildLibrary.flutter.name) {
          return join(appHomeDir.androidDir.path, 'aar', 'flutter');
        } else {
          throw Exception('不支持的构建库: $buildLibrary');
        }
      } else {
        throw Exception('不支持的构建类型: $buildType');
      }
    } else if (buildPlatform == BuildPlatform.ohos.name) {
      if (buildType == BuildType.library.name) {
        return join(appHomeDir.ohosDir.path, 'unityLibrary');
      } else if (buildType == BuildType.har.name) {
        if (buildLibrary == BuildLibrary.flutter.name) {
          final mode =
              buildConfiguration == BuildConfiguration.debug.name
                  ? 'debug'
                  : 'release';
          return join(appHomeDir.ohosDir.path, 'aar', 'flutter', mode);
        } else if (buildLibrary == BuildLibrary.unity.name) {
          return join(appHomeDir.ohosDir.path, 'aar', 'unity');
        }
        throw Exception('不支持的构建库: $buildLibrary');
      } else {
        throw Exception('ohos仅支持 library/har 构建类型: $buildType');
      }
    } else {
      throw Exception('不支持的平台: $buildPlatform');
    }
  }

  /// 使用缓存
  Future<void> useCache(CacheModel cacheModel) async {
    final targetDir = Directory(
      getBinaryCachePath(
        appHomeDir: appHomeDir,
        buildPlatform: buildPlatform,
        buildLibrary: buildLibrary,
        buildType: buildType,
        buildConfiguration: buildConfiguration,
      ),
    );
    final metaxCache = createMetaxCache(int.parse(cacheModel.buildId));
    final zipPath = metaxCache.getZipCachePath(cacheModel.commitHash);
    await copyZipToDir(zipPath, targetDir);

    /// 如果当前是iOS 并且是Flutter则需要复制隐私文件到对应目录
    if (buildPlatform == BuildPlatform.ios.name &&
        buildLibrary == BuildLibrary.flutter.name &&
        buildType == BuildType.framework.name) {
      final privacyDir = Directory(join(
        appHomeDir.iosDir.path,
        'frameworks',
        'Privacys',
      ));
      final targetPrivacyDir = Directory(join(
        appHomeDir.iosDir.path,
        'frameworks',
        'flutter',
        buildConfiguration == BuildConfiguration.release.name
            ? 'Release'
            : 'Debug',
        'Privacys',
      ));
      if (await targetPrivacyDir.exists()) {
        await targetPrivacyDir.delete(recursive: true);
      }
      await copyDirToDir(privacyDir, targetPrivacyDir);
    }
  }

  /// 查询网络是否存在缓存
  Future<CacheModel?> queryNetworkCache() async {
    /// 获取当前网络缓存全部列表
    final appwriteService = AppwriteServer(
      endpoint: appwriteCacheEnvironment.endpoint,
      projectId: appwriteCacheEnvironment.projectId,
      apiKey: appwriteCacheEnvironment.apiKey,
    );
    final zipCacheList = await appwriteService.queryZipCacheList(
      databaseId: appwriteCacheEnvironment.databaseId,
      collectionId: appwriteCacheEnvironment.collectionId,
      platform: buildPlatform,
      isStore: false,
      buildConfiguration: buildConfiguration,
      buildLibrary: buildLibrary,
      buildType: buildType,
    );
    final serverCacheModels =
        zipCacheList.map((e) => ServerCacheModel.fromJson(e)).toList();
    return findCacheInList(serverCacheModels);
  }

  /// 从一组缓存中查找适合的缓存
  CacheModel? findCacheInList(List<CacheModel> cacheModels) {
    /// 查询本地是否存在缓存
    cacheModels = cacheModels
        .where((e) => e.buildPlatform == buildPlatform)
        .where((e) => e.configuration == buildConfiguration)
        .where((e) => e.buildLibrary == buildLibrary)
        .where((e) => e.buildType == buildType)
        .where((e) => e.branch == branch)
        .toList();

    loggerDebug('commitHash: $commitHash buildId: $buildId');
    if (commitHash != null) {
      cacheModels =
          cacheModels.where((e) => e.commitHash == commitHash).toList();
    }

    if (buildId != null) {
      cacheModels = cacheModels.where((e) => e.buildId == buildId).toList();
    }

    if (cacheModels.isEmpty) return null;

    /// 如果是Unity则按照BuildId排序
    /// 如果是Flutter则按照CommitHash排序
    if (buildLibrary == BuildLibrary.flutter.name) {
      cacheModels.sort((a, b) => b.commitTime.compareTo(a.commitTime));
    } else if (buildLibrary == BuildLibrary.unity.name) {
      cacheModels.sort((a, b) {
        final aBuildId = int.parse(a.buildId);
        final bBuildId = int.parse(b.buildId);
        return bBuildId.compareTo(aBuildId);
      });
    } else {
      throw UnimplementedError();
    }

    /// 获取当前分支的最新缓存
    return cacheModels.last;
  }

  /// 编译缓存
  Future<CacheModel?> compileCache() async {
    loggerDebug('缓存不存在,正在编译...');
    if (buildType == BuildType.library.name) {
      await compileUnityLibrary();
    } else {
      if (buildLibrary == BuildLibrary.flutter.name) {
        await compileFlutter();
      } else if (buildLibrary == BuildLibrary.unity.name) {
        final commandLine = [
          'metax',
          'cache',
          'use',
          '--workspace',
          appHomeDir.workspace,
          '--buildPlatform',
          buildPlatform,
          '--buildConfiguration',
          'release',
          '--buildLibrary',
          'unity',
          '--buildType',
          'library',
          '--unityBranch',
          branch,
          isUpload ? '--isUpload' : '--no-isUpload',
          getUseMockCommand(),
          ...getUseCacheCommands(),
        ];
        if (buildId != null) {
          commandLine.add('--buildId');
          commandLine.add(buildId.toString());
        }
        await ProcessRunner().runProcess(
          commandLine,
          printOutput: true,
          workingDirectory: appHomeDir.directory,
        );
        await compileUnity();
      } else {
        throw UnimplementedError();
      }
    }
    return queryLocalCache();
  }

  /// 编译Unity Library
  Future<void> compileUnityLibrary() async {
    loggerDebug('Unity编译目录: ${appHomeDir.workspace}');
    await ProcessRunner().runProcess(
      [
        'metax',
        'build',
        'unity_cache',
        buildPlatform,
        '--workspace',
        appHomeDir.workspace,
        '--unityBranch',
        branch,
        isUpload ? '--isUpload' : '--no-isUpload',
        getUseMockCommand(),
        ...getUseCacheCommands(),
      ],
      printOutput: true,
      workingDirectory: appHomeDir.directory,
    );
  }

  /// 编译Unity（HAR/AAR/Framework 二次打包）
  Future<void> compileUnity() async {
    late String buildType;
    if (buildPlatform == BuildPlatform.ios.name) {
      buildType = BuildType.framework.name;
    } else if (buildPlatform == BuildPlatform.android.name) {
      buildType = BuildType.aar.name;
    } else if (buildPlatform == BuildPlatform.ohos.name) {
      buildType = BuildType.har.name;
    } else {
      throw UnimplementedError();
    }
    loggerDebug('Unity二次打包目录: ${appHomeDir.workspace}');
    await ProcessRunner().runProcess(
      [
        'metax',
        'build',
        buildType,
        'unity',
        '--workspace',
        appHomeDir.workspace,
        isUpload ? '--isUpload' : '--no-isUpload',
        getUseMockCommand(),
        ...getUseCacheCommands(),
      ],
      workingDirectory: appHomeDir.directory,
      printOutput: true,
    );
  }

  /// 编译Flutter
  Future<void> compileFlutter() async {
    late String buildType;
    if (buildPlatform == BuildPlatform.ios.name) {
      buildType = BuildType.framework.name;
    } else if (buildPlatform == BuildPlatform.android.name) {
      buildType = BuildType.aar.name;
    } else if (buildPlatform == BuildPlatform.ohos.name) {
      buildType = BuildType.har.name;
    } else {
      throw UnimplementedError();
    }
    await ProcessRunner().runProcess(
      [
        'metax',
        'build',
        buildType,
        'flutter',
        '--configuration',
        buildConfiguration,
        isUpload ? '--isUpload' : '--no-isUpload',
        getUseMockCommand(),
        ...getUseCacheCommands(),
      ],
      workingDirectory: appHomeDir.directory,
      printOutput: true,
    );
  }
}
