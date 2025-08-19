import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:args/command_runner.dart';
import 'package:crypto/crypto.dart';
import 'package:dart_appwrite/dart_appwrite.dart';
import 'package:dart_appwrite/models.dart' hide File;
import 'package:meta_tool/app_home_dir.dart';
import 'package:meta_tool/appwrite_environment.dart';
import 'package:meta_tool/appwrite_server.dart';
import 'package:meta_tool/argument_get.dart';
import 'package:meta_tool/common.dart';
import 'package:meta_tool/git_submodule_parse.dart';
import 'package:path/path.dart' as p;
import 'package:path/path.dart';
import 'package:process_runner/process_runner.dart';

class FlutterWebCacheCommand extends Command {
  @override
  String get name => 'flutter_web_cache';
  @override
  String get description => 'flutter web cache';

  FlutterWebCacheCommand() {
    argParser.addOption('enable', help: '是否开启热更');
    argParser.addOption('routeName', help: '路由名称');
    argParser.addOption('allow_phones', help: '允许的手机型号列表');
    argParser.addOption('is_store', help: '是否为商店版本');
  }

  @override
  Future<void> run() async {
    final version = DateTime.now().millisecondsSinceEpoch.toString();
    final enable = ArgumentGet(argResults).getString('enable', '是否开启热更(默认true)',
            defaultValue: 'true', allowed: ['true', 'false']) ==
        'true';

    final pagesDir = Directory(
        join(Directory.current.path, 'packages', 'flutter_metax_pages'));
    final pages = pagesDir
        .listSync()
        .whereType<Directory>()
        .map((e) => p.basename(e.path))
        .toList();

    // 获取路由名称参数
    final routeName = ArgumentGet(argResults).getString(
      'routeName',
      '路由名称',
      allowed: pages,
    );
    final allowPhones = ArgumentGet(argResults).getString(
      'allow_phones',
      '允许的手机型号列表(默认为空)',
      defaultValue: '',
    );
    final isStore = ArgumentGet(argResults).getString(
          'is_store',
          '是否为商店版本(默认false)',
          defaultValue: 'false',
          allowed: ['true', 'false'],
        ) ==
        'true';

    // 第一步：执行Dart命令创建Web页面
    final createPageResult = await ProcessRunner().runProcess(
      [
        'dart',
        'run',
        'metaapp_flutter/bin/create_flutter_web_page.dart',
        routeName
      ],
      printOutput: true,
      runInShell: true,
    );

    if (createPageResult.exitCode != 0) {
      throw Exception(
        '创建Web页面失败：\nstdout: ${createPageResult.stdout}\nstderr: ${createPageResult.stderr}',
      );
    }

    // 第二步：执行melos bootstrap
    final melosResult = await ProcessRunner().runProcess(
      [
        'melos',
        'bootstrap',
      ],
      printOutput: true,
      runInShell: true,
    );

    if (melosResult.exitCode != 0) {
      throw Exception(
        'melos bootstrap执行失败：\nstdout: ${melosResult.stdout}\nstderr: ${melosResult.stderr}',
      );
    }

    final Directory webDir = Directory(p.join(
      Directory.current.path,
      'apps',
      'flutter_metax_web',
      'build',
      'web',
    ));
    if (await webDir.exists()) {
      await webDir.delete(recursive: true);
    }

    // 第三步：执行Flutter构建Web命令
    final buildResult = await ProcessRunner().runProcess(
      [
        'flutter',
        'build',
        'web',
        '--release',
        '--web-renderer',
        'html',
      ],
      printOutput: true,
      runInShell: true,
      workingDirectory: Directory(
          p.join(Directory.current.path, 'apps', 'flutter_metax_web')),
    );

    if (buildResult.exitCode != 0) {
      throw Exception(
        'Flutter构建Web失败：\nstdout: ${buildResult.stdout}\nstderr: ${buildResult.stderr}',
      );
    }

    if (!await webDir.exists()) {
      throw Exception('目录 $webDir 不存在');
    }

    final File jsonFile = File(p.join(webDir.path, 'flutter_web_cache.json'));
    final List<Map<String, dynamic>> cacheEntries = [];

    await for (final entity in webDir.list(recursive: true)) {
      if (entity is File) {
        // 排除已生成的ZIP和JSON文件
        final String fileName = p.basename(entity.path);
        if (fileName.endsWith('.zip') || fileName == 'flutter_web_cache.json') {
          continue;
        }

        final String relativePath = p.relative(entity.path, from: webDir.path);
        final List<int> fileBytes = await entity.readAsBytes();
        final String md5Hash = md5.convert(fileBytes).toString();
        final String zipPath = p.join(webDir.path, '$md5Hash.zip');

        // 创建ZIP文件
        final Archive archive = Archive();
        final ArchiveFile archiveFile =
            ArchiveFile(relativePath, fileBytes.length, fileBytes);
        archive.addFile(archiveFile);

        // 写入ZIP文件
        final File zipFile = File(zipPath);
        await zipFile.writeAsBytes(ZipEncoder().encode(archive)!);

        // 添加到缓存条目
        cacheEntries.add({
          'md5': md5Hash,
          'size': fileBytes.length,
          'path': relativePath,
        });
      }
    }

    // 写入JSON文件
    await jsonFile.writeAsString(JsonEncoder().convert(cacheEntries));
    print('Flutter Web缓存信息已生成: ${jsonFile.path}');

    final appwriteEnvironment =
        AppwriteCacheEnvironment(AppHomeDir(Directory.current.path));

    final appwriteServer = AppwriteServer(
      endpoint: appwriteEnvironment.endpoint,
      projectId: appwriteEnvironment.projectId,
      apiKey: appwriteEnvironment.apiKey,
    );

    final databases = Databases(appwriteServer.client);

    final resouceIds = <String>[];
    for (final entry in cacheEntries) {
      final String md5 = entry['md5'];
      final String path = entry['path'];
      final int size = entry['size'];
      final zipFile = File(p.join(webDir.path, '$md5.zip'));
      if (!await zipFile.exists()) {
        throw Exception('ZIP文件不存在: $zipFile');
      }

      /// 查询md5是否已经存在
      final document = await databases.listDocuments(
        databaseId: '67f47b11001a83bd8eb1',
        collectionId: '67f47c64000bb4cafa02',
        queries: [
          Query.equal('md5', md5),
        ],
      ).then<Document?>((value) {
        return value.documents.firstOrNull;
      }).catchError((e) {
        return null;
      });
      if (document == null) {
        final fileId = ID.unique();

        /// 上传zip到67f47aac0019101b3584
        await Storage(appwriteServer.client).createFile(
          bucketId: '67f47aac0019101b3584',
          fileId: fileId,
          file: InputFile.fromPath(path: zipFile.path),
          onProgress: (progress) {
            loggerDebug('上传进度: ${progress.progress}%-[${zipFile.path}]');
          },
        );

        loggerInfo('[$path][$md5]上传完成');

        final resouceId = ID.unique();
        await databases.createDocument(
          databaseId: '67f47b11001a83bd8eb1',
          collectionId: '67f47c64000bb4cafa02',
          documentId: resouceId,
          data: {
            'fileId': fileId,
            'md5': md5,
            'size': size,
            'path': path,
          },
        );
        loggerInfo('[$path][$md5]资源创建成功');

        resouceIds.add(resouceId);
      } else {
        loggerSuccess('[$path][$md5]已经存在，跳过资源上传');
        resouceIds.add(document.$id);
      }
    }

    final workspace = Directory.current.path;
    final gitmodulesPath = p.join(workspace, '.gitmodules');
    final gitSubmodules = await parseGitmodulesFile(gitmodulesPath);
    final flutterWebPackages = await getFlutterModuleVersions(
      workspace: workspace,
      gitSubmodules: gitSubmodules,
    );

    for (final name in flutterWebPackages.keys) {
      final id = ID.unique();
      await databases.createDocument(
        databaseId: '67f47b11001a83bd8eb1',
        collectionId: '68a342350038944c93cf',
        documentId: id,
        data: flutterWebPackages[name]!,
      );
    }
    List<String> packageIds = [];
    final versionId = ID.unique();
    await databases.createDocument(
      databaseId: '67f47b11001a83bd8eb1',
      collectionId: '68a340c0002682fb25ba',
      documentId: versionId,
      data: {
        'version': version,
        'enable': enable,
        'routeName': '/$routeName',
        'resources': resouceIds,
        'allow_phones': allowPhones == '' ? [] : allowPhones.split(','),
        'is_store': isStore,
        'package_ids': packageIds,
      },
    );
    loggerSuccess('发布成功: $version');
  }
}
