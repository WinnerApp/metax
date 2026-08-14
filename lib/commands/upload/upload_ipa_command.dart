import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:meta_tool/common.dart';
import 'package:meta_tool/define.dart';

/// Transporter 包级上传进度，例如：
/// `Package upload progress: 42.50% completed`
final _packageUploadProgress = RegExp(
  r'Package upload progress:\s*(\d+(?:\.\d+)?)\s*%',
  caseSensitive: false,
);

const _progressStepPct = 5;

class UploadIpaCommand extends Command {
  @override
  String get description => '上传ipa';

  @override
  String get name => 'ipa';

  UploadIpaCommand() {
    argParser.addOption(
      'ipa',
      help: 'ipa文件路径',
      mandatory: true,
    );

    argParser.addOption(
      'log',
      help: '构建日志',
    );
  }

  @override
  Future run() async {
    String ipa = argResults?['ipa'];
    String? log = argResults?['log'];
    if (!File(ipa).existsSync()) {
      throw Exception('$ipa文件不存在');
    }

    loggerDebug('开始上传 IPA 到 TestFlight...');

    final process = await Process.start(
      'fastlane',
      [
        'upload_testflight',
        'ipa:$ipa',
        "changelog:'$log'",
        '--verbose',
      ],
      workingDirectory: appHomeDir.iosDir.path,
    );

    var lastPrintedPct = -_progressStepPct;

    void handleLine(String line) {
      final trimmed = line.trimRight();
      if (trimmed.isEmpty) return;

      final progressMatch = _packageUploadProgress.firstMatch(trimmed);
      if (progressMatch != null) {
        final pct = double.parse(progressMatch.group(1)!).floor().clamp(0, 100);
        final shouldPrint = pct >= lastPrintedPct + _progressStepPct ||
            (pct >= 100 && lastPrintedPct < 100);
        if (shouldPrint) {
          lastPrintedPct = pct >= 100 ? 100 : pct - (pct % _progressStepPct);
          loggerDebug('上传进度: $pct%');
        }
        return;
      }

      // --verbose 下 Transporter DEBUG 刷屏，保留非 DEBUG 与错误信息
      if (RegExp(r'\bDEBUG\b').hasMatch(trimmed) &&
          !RegExp(r'\bERROR\b|\bWARN(?:ING)?\b').hasMatch(trimmed)) {
        return;
      }

      stdout.writeln(trimmed);
    }

    await Future.wait([
      process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .forEach(handleLine),
      process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .forEach(handleLine),
    ]);

    final exitCode = await process.exitCode;
    if (exitCode != 0) {
      throw Exception('fastlane upload_testflight 失败，exitCode=$exitCode');
    }
    loggerSuccess('上传成功');
  }
}
