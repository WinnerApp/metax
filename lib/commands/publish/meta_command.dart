import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dart_appwrite/dart_appwrite.dart';
import 'package:meta_tool/common.dart';
import 'package:path/path.dart';
import 'package:process_runner/process_runner.dart';
import 'package:prompts/prompts.dart' as prompts;

class MetaCommand extends Command {
  @override
  String get description => '发布棉宇宙工具';

  @override
  String get name => 'metax';

  @override
  FutureOr? run() async {
    if (Platform.environment['APPWRITE_ENDPOINT'] == null) {
      throw Exception('请设置APPWRITE_ENDPOINT');
    }
    if (Platform.environment['APPWRITE_API_KEY'] == null) {
      throw Exception('请设置APPWRITE_API_KEY');
    }
    if (Platform.environment['APPWRITE_PROJECT_ID'] == null) {
      throw Exception('请设置APPWRITE_PROJECT_ID');
    }
    if (Platform.environment['APPWRITE_BUCKET_ID'] == null) {
      throw Exception('请设置APPWRITE_BUCKET_ID');
    }
    final projectId = Platform.environment['APPWRITE_PROJECT_ID']!;
    final bucketId = Platform.environment['APPWRITE_BUCKET_ID']!;
    final client = Client(endPoint: Platform.environment['APPWRITE_ENDPOINT']!)
      ..setProject(projectId)
      ..setKey(Platform.environment['APPWRITE_API_KEY']!);
    final workspace = Directory.current.path;
    final metaxRubyFile = File(join(workspace, 'metax.rb'));
    if (!metaxRubyFile.existsSync()) {
      throw Exception('请在metax.rb的项目目录进行发布');
    }
    final version = prompts.get('请输入版本号');
    final metaxPath = prompts.get('请输入metax的路径');
    final sha256 = await (() async {
      // 优先 openssl；Windows 没装 openssl 时用 certutil
      if (await isCommandAvailable('openssl')) {
        return await ProcessRunner().runProcess(
          ['openssl', 'sha256', metaxPath],
          printOutput: true,
        ).then((e) => e.stdout.toString().trim().split('=').last.trim());
      }
      if (Platform.isWindows && await isCommandAvailable('certutil')) {
        final out = await ProcessRunner().runProcess(
          ['certutil', '-hashfile', metaxPath, 'SHA256'],
          printOutput: true,
        ).then((e) => e.stdout.toString());
        // certutil 输出里会有一行纯 hash
        final lines = out
            .split('\n')
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty)
            .toList();
        final hashLine = lines.firstWhere(
          (l) => RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(l),
          orElse: () => throw Exception('certutil 输出无法解析 SHA256'),
        );
        return hashLine.toLowerCase();
      }
      throw Exception('计算 SHA256 失败：未找到 openssl（Windows 可安装 openssl 或确保 certutil 可用）');
    })();

    final storage = Storage(client);
    String fileId = ID.unique();
    final fileName = '$version-$sha256';
    final cacheFile = await storage.listFiles(
      bucketId: bucketId,
      queries: [
        Query.equal('name', fileName),
        Query.orderDesc('\$createdAt'),
      ],
    );
    if (cacheFile.total > 0) {
      fileId = cacheFile.files.first.$id;
    } else {
      await storage.createFile(
        bucketId: bucketId,
        fileId: fileId,
        file: InputFile.fromBytes(
          bytes: await File(metaxPath).readAsBytes(),
          filename: '$version-$sha256',
        ),
        onProgress: (p0) {
          loggerDebug('上传进度: ${p0.progress}%');
        },
      );
    }

    final downloadUrl =
        'https://appwrite.winnermedical.com/v1/storage/buckets/$bucketId/files/$fileId/download?project=$projectId&mode=admin';

    final metaxRubyContent = '''
# Metax.rb
class Metax < Formula
    desc "棉宇宙app开发工具"
    homepage "https://github.com/WinnerApp/metax"
    url "$downloadUrl"
    sha256 "$sha256"
    license "MIT"
    version "$version"
  
    def install
      File.rename("$version-$sha256", "metax")
      bin.install "metax"
    end
  
    def test
      system "#{bin}/metax", "--help"
    end
end
''';
    final oldMetaxRubyContent = await metaxRubyFile.readAsString();
    if (oldMetaxRubyContent == metaxRubyContent) {
      loggerDebug('版本号相同，跳过发布');
      return;
    }
    await metaxRubyFile.writeAsString(metaxRubyContent);
    await ProcessRunner().runProcess(
      [
        'git',
        'add',
        'metax.rb',
      ],
      printOutput: true,
    );
    await ProcessRunner().runProcess(
      [
        'git',
        'commit',
        '-m',
        '发布棉宇宙工具$version',
      ],
      printOutput: true,
    );
    await ProcessRunner().runProcess(
      [
        'git',
        'push',
        'origin',
        'master',
      ],
      printOutput: true,
    );
    loggerSuccess('发布成功');
  }
}
