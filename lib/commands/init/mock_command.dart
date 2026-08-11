import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:meta_tool/common.dart';
import 'package:meta_tool/define.dart';
import 'package:path/path.dart';
import 'package:prompts/prompts.dart' as prompts;

class MockCommand extends Command {
  @override
  String get name => 'mock';

  @override
  String get description => '初始化mock数据,对于测试编译进行加速';

  @override
  FutureOr? run() async {
    final mockDir = Directory(join(appHomeDir.workspace, 'ignores', 'mock'));
    if (!mockDir.existsSync()) {
      mockDir.createSync(recursive: true);
    }
    for (final mockType in MockType.values) {
      final isInit = prompts.choose('是否初始化mock缓存$mockType', ['false', 'true']);
      if (isInit != 'true') continue;
      final mokeCacheDir = mockType.mockDir(appHomeDir);
      final sourceCacheDir = prompts.get('请输入mock缓存的路径地址');
      final verifySourceCacheDir = await Future.sync(() async {
        final verifySourceCacheEntry = switch (mockType) {
          MockType.iosUnityLibrary =>
            File(join(sourceCacheDir, 'UnityFramework', 'UnityFramework.h')),
          MockType.androidUnityLibrary =>
            File(join(sourceCacheDir, 'libs', 'unity-classes.jar')),
          MockType.ohosUnityLibrary => Directory(sourceCacheDir),
          MockType.flutterAar => Directory(join(
              sourceCacheDir,
              'outputs',
              'repo',
              'com',
              'winner',
              'meta_flutter',
            )),
          MockType.flutterHar => Directory(sourceCacheDir),
          MockType.flutterFramework =>
            Directory(join(sourceCacheDir, 'App.xcframework')),
          MockType.unityAar => File(join(
              sourceCacheDir,
              'unityLibrary-release.aar',
            )),
          MockType.unityHar => Directory(sourceCacheDir),
          MockType.unityFramework =>
            Directory(join(sourceCacheDir, 'UnityFramework.xcframework')),
          MockType.ipa => File(join(sourceCacheDir, 'meta_winner_app.ipa')),
          MockType.apk => File(join(sourceCacheDir, 'meta_winner_app.apk')),
        };
        return verifySourceCacheEntry.existsSync();
      });
      if (!verifySourceCacheDir) {
        throw Exception('mock缓存路径错误,请重新输入');
      }
      await copyDirToDir(Directory(sourceCacheDir), mokeCacheDir);
    }
  }
}
