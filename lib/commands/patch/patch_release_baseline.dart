import 'dart:io';

import 'package:meta_tool/app_home_dir.dart';
import 'package:meta_tool/appwrite_environment.dart';
import 'package:meta_tool/appwrite_server.dart';
import 'package:meta_tool/commands/patch/patch_compat_gate.dart';
import 'package:meta_tool/common.dart';
import 'package:meta_tool/shorebird.dart';
import 'package:meta_tool/unity_environment.dart';
import 'package:path/path.dart';
import 'package:process_runner/process_runner.dart';

/// 从 Appwrite 打包记录解析热更预审用的多仓库基线。
class PatchReleaseBaselineResolver {
  PatchReleaseBaselineResolver({
    required this.appHomeDir,
    required this.platform,
  });

  final AppHomeDir appHomeDir;
  final String platform; // ios | android

  /// 查询 `buildName+buildNumber` 对应发版时各 submodule + Unity 的 commit。
  Future<List<PatchRepoBaseline>> resolve({
    required String releaseVersion,
    String? preferMelosBranch,
  }) async {
    final parsed = parseShorebirdReleaseVersion(releaseVersion);
    final buildEnv = AppwriteBuildEnvironment(appHomeDir);
    final server = AppwriteServer(
      endpoint: buildEnv.endpoint,
      projectId: buildEnv.projectId,
      apiKey: buildEnv.apiKey,
    );

    String? melosBranch = preferMelosBranch?.trim();
    if (melosBranch == null || melosBranch.isEmpty) {
      try {
        melosBranch = await getCurrentBranch(appHomeDir.workspace);
      } catch (_) {
        melosBranch = null;
      }
    }

    final buildDoc = await server.queryBuildConfigByVersion(
      databaseId: buildEnv.databaseId,
      buildConfigCollectionId: buildEnv.buildConfigCollectionId,
      platform: platform,
      buildName: parsed.buildName,
      buildNumber: parsed.buildNumber,
      preferMelosBranch: melosBranch,
    );

    if (buildDoc == null) {
      throw Exception(
        '未找到打包记录: platform=$platform '
        'version=${parsed.buildName}+${parsed.buildNumber}'
        '${melosBranch == null ? '' : ' (prefer melos_branch=$melosBranch)'}。'
        '请确认该版本曾用 metax upload 出包，或使用 --force-patch 跳过预审。',
      );
    }

    loggerInfo(
      '热更预审基线打包记录: id=${buildDoc.$id} '
      'melos_branch=${buildDoc.data['melos_branch']} '
      'unity_branch=${buildDoc.data['unity_branch']} '
      'build=${buildDoc.data['build_name']}+${buildDoc.data['build_number']}',
    );

    final branchConfigs = await server.queryBuildBranchConfig(
      databaseId: buildEnv.databaseId,
      buildBranchConfigCollectionId: buildEnv.buildBranchConfigCollectionId,
      buildId: buildDoc.$id,
    );

    final baselines = <PatchRepoBaseline>[];
    final seenPaths = <String>{};

    if (branchConfigs != null) {
      for (final doc in branchConfigs.documents) {
        final path = doc.data['path']?.toString().trim() ?? '';
        final commitId = doc.data['commit_id']?.toString().trim() ?? '';
        final branch = doc.data['branch']?.toString() ?? '';
        if (path.isEmpty || commitId.isEmpty) continue;
        if (!seenPaths.add(path)) continue;

        final abs = join(appHomeDir.workspace, path);
        loggerInfo(
          '  submodule 基线: $path@$commitId'
          '${branch.isEmpty ? '' : ' (branch=$branch)'}',
        );
        baselines.add(PatchRepoBaseline(
          label: path,
          workingDirectory: abs,
          baseCommit: commitId,
          pathPrefix: path,
        ));
      }
    }

    final unityCommit =
        buildDoc.data['unity_commit_id']?.toString().trim() ?? '';
    if (unityCommit.isNotEmpty) {
      try {
        final unityEnv = UnityEnvironment.fromEnvironment(appHomeDir);
        final unityRoot = unityEnv.getPlatfromUnityWorkspace(platform);
        loggerInfo('  unity 基线: $unityRoot@$unityCommit');
        baselines.add(PatchRepoBaseline(
          label: 'unity',
          workingDirectory: unityRoot,
          baseCommit: unityCommit,
          pathPrefix: 'unity',
          isUnity: true,
        ));
      } catch (e) {
        loggerWarning('无法解析 Unity 工作区，跳过 Unity 预审: $e');
      }
    }

    // 打包记录未存 melos 根 commit；根目录仅兜底预审相对 HEAD 的未提交改动。
    await _appendRootUncommittedGate(baselines);

    if (baselines.isEmpty) {
      throw Exception(
        '打包记录 ${buildDoc.$id} 未包含任何 submodule/Unity commit，无法做多仓库预审。'
        '排障可加 --force-patch。',
      );
    }
    return baselines;
  }

  Future<void> _appendRootUncommittedGate(
    List<PatchRepoBaseline> baselines,
  ) async {
    final root = appHomeDir.workspace;
    final gitDir = Directory(join(root, '.git'));
    final gitFile = File(join(root, '.git'));
    if (!gitDir.existsSync() && !gitFile.existsSync()) {
      return;
    }
    try {
      final head = (await ProcessRunner().runProcess(
        ['git', 'rev-parse', 'HEAD'],
        workingDirectory: Directory(root),
        printOutput: false,
      ))
          .stdout
          .toString()
          .trim();
      if (head.isEmpty) return;
      baselines.add(PatchRepoBaseline(
        label: 'workspace-root(uncommitted)',
        workingDirectory: root,
        baseCommit: head,
        pathPrefix: '',
      ));
      loggerInfo(
        '  workspace 根目录：仅预审相对 HEAD 的未提交改动（打包记录无根 commit）',
      );
    } catch (e) {
      loggerWarning('跳过 workspace 根目录未提交预审: $e');
    }
  }
}
