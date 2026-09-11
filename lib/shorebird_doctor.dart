import 'dart:io';

import 'package:meta_tool/app_home_dir.dart';
import 'package:meta_tool/doctor.dart';
import 'package:meta_tool/flutter_sdk.dart';
import 'package:meta_tool/meta_ota.dart';
import 'package:meta_tool/shorebird.dart';
import 'package:process_runner/process_runner.dart';

/// 打包机 / CI Shorebird 环境预检（不真正出包）。
class ShorebirdDoctor {
  final AppHomeDir appHomeDir;
  final Map<String, String> environment;
  final bool checkPatch;
  final bool checkNetwork;
  final Duration networkTimeout;
  final ProcessRunner? processRunner;

  ShorebirdDoctor({
    required this.appHomeDir,
    Map<String, String>? environment,
    this.checkPatch = false,
    this.checkNetwork = true,
    this.networkTimeout = const Duration(seconds: 8),
    this.processRunner,
  }) : environment = Map<String, String>.from(
          environment ?? Platform.environment,
        );

  Future<DoctorReport> run() async {
    final items = <DoctorCheckItem>[];

    final cli = await _checkShorebirdCli();
    items.add(cli);

    items.add(await _checkAuth(cliOk: cli.ok));
    if (checkNetwork) {
      items.addAll(await _checkNetwork());
    }
    items.add(_checkHostedUrlEnv());
    items.add(_checkProjectYaml());
    items.add(_checkFlutterVersion());
    items.add(_checkEnabledFlag());

    if (checkPatch) {
      items.add(await _checkMetaOtaBin());
      items.add(_checkMetaOtaCredentials());
    }

    return DoctorReport([
      for (final item in items)
        item.group == null ? item.copyWith(group: 'shorebird') : item,
    ]);
  }

  ProcessRunner get _runner => processRunner ?? ProcessRunner();

  Future<DoctorCheckItem> _checkShorebirdCli() async {
    final cli = resolveFlutterPatchCli(environment);
    try {
      if (cli.contains(Platform.pathSeparator) || cli.startsWith('.')) {
        if (!File(cli).existsSync()) {
          return _cliMissing(cli);
        }
        return DoctorCheckItem(
          id: 'shorebird_cli',
          title: 'FlutterPatch CLI',
          ok: true,
          severity: DoctorCheckSeverity.info,
          detail: cli,
          group: 'shorebird',
        );
      }
      final which = await _runner.runProcess(
        ['which', cli],
        printOutput: false,
      );
      final path = which.stdout.trim();
      if (path.isEmpty) {
        return _cliMissing(cli);
      }

      return DoctorCheckItem(
        id: 'shorebird_cli',
        title: 'FlutterPatch CLI',
        ok: true,
        severity: DoctorCheckSeverity.info,
        detail: path,
        group: 'shorebird',
      );
    } catch (_) {
      return _cliMissing(cli);
    }
  }

  DoctorCheckItem _cliMissing([String cli = kFlutterPatchCliName]) {
    return DoctorCheckItem(
      id: 'shorebird_cli',
      title: 'FlutterPatch CLI',
      ok: false,
      severity: DoctorCheckSeverity.error,
      detail: 'PATH 中未找到 $cli',
      fix: '安装 FlutterPatch 到 ~/.flutterpatch/bin 并加入 PATH，'
          '或设置 FLUTTERPATCH_BIN=$cli\n'
          '见 flutterpatch downloads/install_cli.sh',
      group: 'shorebird',
    );
  }

  Future<DoctorCheckItem> _checkAuth({required bool cliOk}) async {
    final flutterPatchToken = (environment['FLUTTERPATCH_TOKEN'] ?? '').trim();
    if (flutterPatchToken.isNotEmpty) {
      return DoctorCheckItem(
        id: 'shorebird_auth',
        title: 'FlutterPatch 鉴权',
        ok: true,
        severity: DoctorCheckSeverity.info,
        detail: cliOk
            ? 'FLUTTERPATCH_TOKEN 已设置'
            : 'FLUTTERPATCH_TOKEN 已设置（CLI 缺失）',
      );
    }

    final legacy = (environment['SHOREBIRD_TOKEN'] ?? '').trim();
    if (legacy.isNotEmpty) {
      return const DoctorCheckItem(
        id: 'shorebird_auth',
        title: 'FlutterPatch 鉴权',
        ok: false,
        severity: DoctorCheckSeverity.warning,
        detail: '检测到 SHOREBIRD_TOKEN，FlutterPatch 请改用 FLUTTERPATCH_TOKEN',
        fix: 'export FLUTTERPATCH_TOKEN=<control_api Bearer>',
      );
    }

    return DoctorCheckItem(
      id: 'shorebird_auth',
      title: 'FlutterPatch 鉴权',
      ok: false,
      severity: DoctorCheckSeverity.error,
      detail: '未设置 FLUTTERPATCH_TOKEN'
          '${cliOk ? '' : '，且 CLI 不可用'}',
      fix: '打包机/CI 配置 FLUTTERPATCH_TOKEN',
    );
  }

  Future<List<DoctorCheckItem>> _checkNetwork() async {
    final items = <DoctorCheckItem>[
      await _probeUrl(
        id: 'network_download',
        title: '连通 download.shorebird.dev',
        url: kShorebirdFlutterStorageBaseUrl,
        fix: '打包机需能下载 Shorebird Flutter 引擎。'
            '请放行 https://download.shorebird.dev\n'
            '首次 release 会拉引擎，网络不通会拖到打包末尾才失败',
      ),
    ];
    final yaml = ShorebirdYamlConfig.tryLoad(appHomeDir.flutterDir);
    final baseUrl = yaml?.baseUrl?.trim() ?? '';
    if (baseUrl.isNotEmpty) {
      items.insert(
        0,
        await _probeUrl(
          id: 'network_api',
          title: '连通 FlutterPatch 控制面',
          url: baseUrl,
          fix: '打包机需能访问 shorebird.yaml base_url（FlutterPatch control_api）',
        ),
      );
    }
    return items;
  }

  Future<DoctorCheckItem> _probeUrl({
    required String id,
    required String title,
    required String url,
    required String fix,
  }) async {
    final seconds = networkTimeout.inSeconds.clamp(1, 60);
    try {
      final result = await Process.run(
        'curl',
        [
          '-sS',
          '-o',
          '/dev/null',
          '-w',
          '%{http_code}',
          '-m',
          '$seconds',
          '-L',
          url,
        ],
        environment: environment,
        runInShell: false,
      );
      final code = int.tryParse(result.stdout.toString().trim()) ?? 0;
      // 2xx/3xx/4xx 都说明 TCP/TLS 通（401/404 也算通）
      if (code >= 200 && code < 500) {
        return DoctorCheckItem(
          id: id,
          title: title,
          ok: true,
          severity: DoctorCheckSeverity.info,
          detail: 'HTTP $code · $url',
        );
      }
      final err = result.stderr.toString().trim();
      return DoctorCheckItem(
        id: id,
        title: title,
        ok: false,
        severity: DoctorCheckSeverity.error,
        detail: 'HTTP $code · $url'
            '${err.isEmpty ? '' : '\n$err'}',
        fix: fix,
      );
    } catch (e) {
      return DoctorCheckItem(
        id: id,
        title: title,
        ok: false,
        severity: DoctorCheckSeverity.error,
        detail: '探测失败: $e',
        fix: fix,
      );
    }
  }

  DoctorCheckItem _checkHostedUrlEnv() {
    final hosted = (environment['SHOREBIRD_HOSTED_URL'] ?? '').trim();
    final storage = (environment['FLUTTER_STORAGE_BASE_URL'] ?? '').trim();
    final notes = <String>[];

    if (hosted.isNotEmpty) {
      notes.add(
        '环境变量 SHOREBIRD_HOSTED_URL=$hosted '
        '对 FlutterPatch 无效（控制面只读 shorebird.yaml base_url）；'
        'metax 出包时会移除该变量',
      );
    }
    if (storage.isNotEmpty &&
        !_sameHost(storage, kShorebirdFlutterStorageBaseUrl) &&
        !storage.contains('shorebird.dev')) {
      notes.add(
        '环境变量 FLUTTER_STORAGE_BASE_URL=$storage '
        '可能指向国内 Flutter 镜像；metax 出包时会强制覆盖为 '
        '$kShorebirdFlutterStorageBaseUrl',
      );
    }

    if (notes.isEmpty) {
      return DoctorCheckItem(
        id: 'env_override',
        title: 'CLI 环境覆盖',
        ok: true,
        severity: DoctorCheckSeverity.info,
        detail: hosted.isEmpty && storage.isEmpty
            ? '未误配 SHOREBIRD_HOSTED_URL / FLUTTER_STORAGE_BASE_URL'
            : '当前 env 可被 metax 安全处理 '
                '(hosted=${hosted.isEmpty ? '(unset)' : hosted}, '
                'storage=${storage.isEmpty ? '(unset)' : storage})',
      );
    }

    return DoctorCheckItem(
      id: 'env_override',
      title: 'CLI 环境覆盖',
      ok: false,
      severity: DoctorCheckSeverity.warning,
      detail: notes.join('\n'),
      fix: '设备 OTA / 控制面用 shorebird.yaml base_url；'
          '鉴权用 FLUTTERPATCH_TOKEN；不要设 SHOREBIRD_HOSTED_URL',
    );
  }

  DoctorCheckItem _checkProjectYaml() {
    final flutterDir = appHomeDir.flutterDir;
    if (!flutterDir.existsSync()) {
      return DoctorCheckItem(
        id: 'shorebird_yaml',
        title: 'shorebird.yaml',
        ok: false,
        severity: DoctorCheckSeverity.error,
        detail: 'Flutter 目录不存在: ${flutterDir.path}',
        fix: '在 app 仓库根目录执行，或传 --workspace',
      );
    }

    final yaml = ShorebirdYamlConfig.tryLoad(flutterDir);
    final path = ShorebirdYamlConfig.yamlFile(flutterDir).path;
    if (yaml == null) {
      return DoctorCheckItem(
        id: 'shorebird_yaml',
        title: 'shorebird.yaml',
        ok: false,
        severity: DoctorCheckSeverity.error,
        detail: '缺少 $path',
        fix: 'metax init shorebird --writeExample，再填入真实 app_id / base_url',
      );
    }
    final appId = yaml.appId?.trim() ?? '';
    if (appId.isEmpty) {
      return DoctorCheckItem(
        id: 'shorebird_yaml',
        title: 'shorebird.yaml',
        ok: false,
        severity: DoctorCheckSeverity.error,
        detail: '存在 $path 但缺少 app_id',
        fix: '在 shorebird.yaml 写入 Shorebird Console 的 app_id',
      );
    }
    final baseUrl = yaml.baseUrl?.trim() ?? '';
    return DoctorCheckItem(
      id: 'shorebird_yaml',
      title: 'shorebird.yaml',
      ok: true,
      severity: DoctorCheckSeverity.info,
      detail: 'app_id=$appId'
          '${baseUrl.isEmpty ? '' : ' · base_url=$baseUrl'}',
    );
  }

  DoctorCheckItem _checkFlutterVersion() {
    final flutterDir = appHomeDir.flutterDir;
    try {
      final version = resolveShorebirdFlutterVersion(
        flutterDir: flutterDir,
        workspaceDir: Directory(appHomeDir.workspace),
      );
      final configDir = findFvmConfigDir(
        flutterDir,
        stopAt: Directory(appHomeDir.workspace),
      );
      final configured = configDir == null
          ? null
          : readConfiguredFvmVersion(configDir);
      final where = configDir == null
          ? ''
          : ' @ ${configDir.path}';
      return DoctorCheckItem(
        id: 'flutter_version',
        title: 'Shorebird --flutter-version',
        ok: true,
        severity: DoctorCheckSeverity.info,
        detail: configured == null || configured == version
            ? '$version$where'
            : '$version（配置=$configured$where）',
      );
    } catch (e) {
      return DoctorCheckItem(
        id: 'flutter_version',
        title: 'Shorebird --flutter-version',
        ok: false,
        severity: DoctorCheckSeverity.error,
        detail: '$e',
        fix: '在 melos 仓库根或 metaapp_flutter 配置 .fvmrc（如 3.27.4）',
      );
    }
  }

  DoctorCheckItem _checkEnabledFlag() {
    final resolved = resolveUseShorebird(
      appHomeDir: appHomeDir,
      environment: environment,
    );
    if (resolved.enabled) {
      return DoctorCheckItem(
        id: 'shorebird_enabled',
        title: 'Shorebird 开关',
        ok: true,
        severity: DoctorCheckSeverity.info,
        detail: 'enabled=true（${resolved.reason}）',
      );
    }
    return DoctorCheckItem(
      id: 'shorebird_enabled',
      title: 'Shorebird 开关',
      ok: false,
      severity: DoctorCheckSeverity.warning,
      detail: '当前未启用（${resolved.reason}）——机器就绪后打包仍会走普通 Flutter',
      fix: 'pubspec.yaml 设置 metax.shorebird_enabled: true，'
          '或 SHOREBIRD_ENABLED=true / --useShorebird',
    );
  }

  Future<DoctorCheckItem> _checkMetaOtaBin() async {
    try {
      final bin = await resolveMetaOtaBin(environment: environment);
      return DoctorCheckItem(
        id: 'meta_ota_bin',
        title: 'meta_ota CLI',
        ok: true,
        severity: DoctorCheckSeverity.info,
        detail: bin,
      );
    } catch (e) {
      return DoctorCheckItem(
        id: 'meta_ota_bin',
        title: 'meta_ota CLI',
        ok: false,
        severity: DoctorCheckSeverity.error,
        detail: '$e',
        fix: '编译 meta_code_push ota_cli，设置 META_OTA_BIN 或 META_CODE_PUSH_ROOT',
      );
    }
  }

  DoctorCheckItem _checkMetaOtaCredentials() {
    final fileCfg = loadMetaOtaFileConfig(
      appHomeDir.flutterDir,
      environment: environment,
    );
    final api = (environment['META_OTA_API'] ?? '').trim().isNotEmpty
        ? environment['META_OTA_API']!.trim()
        : (fileCfg.api ?? '');
    final token = (environment['META_OTA_TOKEN'] ?? '').trim().isNotEmpty
        ? environment['META_OTA_TOKEN']!.trim()
        : (fileCfg.token ?? '');
    final yaml = ShorebirdYamlConfig.tryLoad(appHomeDir.flutterDir);
    final baseUrl = yaml?.baseUrl?.trim() ?? '';

    final effectiveApi = api.isNotEmpty
        ? api
        : (baseUrl.isNotEmpty ? baseUrl : '');

    if (effectiveApi.isEmpty || token.isEmpty) {
      return DoctorCheckItem(
        id: 'meta_ota_creds',
        title: 'Meta OTA 凭据',
        ok: false,
        severity: DoctorCheckSeverity.error,
        detail: 'api=${effectiveApi.isEmpty ? '(missing)' : effectiveApi} · '
            'token=${token.isEmpty ? '(missing)' : '(set)'}',
        fix: '设置 META_OTA_API / META_OTA_TOKEN，'
            '或 meta_ota config --api/--token，'
            '或在 shorebird.yaml 写 base_url（仅补 api）',
      );
    }

    return DoctorCheckItem(
      id: 'meta_ota_creds',
      title: 'Meta OTA 凭据',
      ok: true,
      severity: DoctorCheckSeverity.info,
      detail: 'api=$effectiveApi · token=(set)',
    );
  }
}

bool _sameHost(String a, String b) {
  Uri? pa;
  Uri? pb;
  try {
    pa = Uri.parse(a);
    pb = Uri.parse(b);
  } catch (_) {
    return a.trim().toLowerCase() == b.trim().toLowerCase();
  }
  return (pa.host).toLowerCase() == (pb.host).toLowerCase();
}
