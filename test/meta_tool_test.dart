import 'package:meta_tool/cache/build_cache.dart';
import 'package:meta_tool/cache/unity_cache.dart';
import 'package:meta_tool/commands/build/build_cache_command.dart';
import 'package:meta_tool/define.dart';
import 'package:test/test.dart';

class MockBuildCacheCommand extends BuildCacheCommand {
  @override
  String get description => '';

  @override
  String get name => '';

  @override
  Future<void> run() async {
    return super.run();
  }
}

void main() {
  test('test can use build cache', () async {
    final command = MockBuildCacheCommand();
    final result = await command.isCacheExitsInBuildDir(
      UnityCache(buildPlatform: BuildPlatform.ios, branch: '1.5.0'),
      '/Users/king/Documents/winner-docs/meta_app/ios/UnityLibrary',
    );
    expect(result, true);
  });
}
