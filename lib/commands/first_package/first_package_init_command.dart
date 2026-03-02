import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:meta_tool/argument_get.dart';
import 'package:meta_tool/commands/first_package/first_package_config.dart';
import 'package:meta_tool/common.dart';

class FirstPackageInitCommand extends Command {
  @override
  String get name => 'init';

  @override
  String get description => '初始化或重置首包配置文件（从用户提供的配置文件复制到缓存目录）';

  FirstPackageInitCommand() {
    argParser.addOption(
      'config',
      help: '首包配置文件路径（例如 .env 文件）',
    );
  }

  @override
  FutureOr? run() async {
    final targetConfigFile = getFirstPackageConfigFile();
    loggerDebug('targetConfigFile: ${targetConfigFile.path}');
    final cacheDir = targetConfigFile.parent;

    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }

    final argumentGet = ArgumentGet(argResults);
    final sourceConfigPath = argumentGet.getString(
      'config',
      '请输入首包配置文件路径（需包含 APPWRITE_ZIP_DATABASE_ID / APPWRITE_ZIP_COLLECTION_ID / APPWRITE_ZIP_BUCKET_ID 等变量）',
    );
    final sourceConfigFile = File(sourceConfigPath);

    if (!await sourceConfigFile.exists()) {
      throw '配置文件不存在: $sourceConfigPath';
    }

    if (await targetConfigFile.exists()) {
      loggerInfo('检测到已有首包配置文件，准备重置: ${targetConfigFile.path}');
      await targetConfigFile.delete();
    }

    await sourceConfigFile.copy(targetConfigFile.path);

    loggerSuccess(
      '首包配置文件已复制到缓存目录: ${targetConfigFile.path}',
    );
    loggerInfo(
      '可选：在配置中增加 FIRST_PACKAGE_IOS_NOTIFY_URL / FIRST_PACKAGE_ANDROID_NOTIFY_URL（首包上传成功后飞书机器人通知链接）',
    );
  }
}
