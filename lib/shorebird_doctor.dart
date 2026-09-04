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
    try {
      final which = await _runner.runProcess(
        ['which', 'shorebird'],
        printOutput: false,
      );
      final path = which.stdout.trim();
      if (path.isEmpty) {
        return _cliMissing();
      }

      return DoctorCheckItem(
        id: 'shorebird_cli',
        title: 'Shorebird CLI',
        ok: true,
        severity: DoctorCheckSeverity.info,
        detail: path,
        group: 'shorebird',
      );
    } catch (_) {
      return _cliMissing();
    }
  }

  DoctorCheckItem _cliMissing() {
    return const DoctorCheckItem(
      id: 'shorebird_cli',
      title: 'Shorebird CLI',
      ok: false,
      severity: DoctorCheckSeverity.error,
      detail: 'PATH 中未找到 shorebird',
      fix: 'curl --proto "=https" --tlsv1.2 '
          'https://raw.githubusercontent.com/shorebirdtech/install/main/install.sh '
          '-sSf | bash\n'
          'Jenkins 非交互 shell 需保证 ~/.shorebird/bin 在 PATH '
          '（或软链到 /usr/local/bin）',
      group: 'shorebird',
    );
  }

  Future<DoctorCheckItem> _checkAuth({required bool cliOk}) async {
    final token = (environment['SHOREBIRD_TOKEN'] ?? '').trim();
    if (token.isNotEmpty) {
      if (!_looksLikeShorebirdToken(token)) {
        return const DoctorCheckItem(
          id: 'shorebird_auth',
          title: 'Shorebird 鉴权',
          ok: false,
          severity: DoctorCheckSeverity.error,
          detail: 'SHOREBIRD_TOKEN 已设置，但格式不像 API Key',
          fix: 'CI 使用 Console API Key（通常以 sb_api_ 开头），'
              '见 https://console.shorebird.dev → Account → API Keys',
        );
      }
      if (!cliOk) {
        return const DoctorCheckItem(
          id: 'shorebird_auth',
          title: 'Shorebird 鉴权',
          ok: true,
          severity: DoctorCheckSeverity.info,
          detail: 'SHOREBIRD_TOKEN 已设置（CLI 缺失，未做 whoami 校验）',
        );
      }
      if (!checkNetwork) {
        return const DoctorCheckItem(
          id: 'shorebird_auth',
          title: 'Shorebird 鉴权',
          ok: true,
          severity: DoctorCheckSeverity.info,
          detail: 'SHOREBIRD_TOKEN 已设置（已跳过网络 / whoami）',
        );
      }
      // 有 token 时 whoami 会走 token；失败则 token 无效或网络不通
      return _whoamiCheck(
        okDetailPrefix: 'SHOREBIRD_TOKEN OK',
        failDetailPrefix: 'SHOREBIRD_TOKEN 存在但 whoami 失败',
        failFix: '检查 token 是否过期/权限不足，以及能否访问 '
            '$kShorebirdOfficialHostedUrl',
      );
    }

    if (!cliOk) {
      return const DoctorCheckItem(
        id: 'shorebird_auth',
        title: 'Shorebird 鉴权',
        ok: false,
        severity: DoctorCheckSeverity.error,
        detail: '未设置 SHOREBIRD_TOKEN，且 CLI 不可用',
        fix: '打包机请配置环境变量 SHOREBIRD_TOKEN；'
            '本机可 shorebird login',
      );
    }

    if (!checkNetwork) {
      return const DoctorCheckItem(
        id: 'shorebird_auth',
        title: 'Shorebird 鉴权',
        ok: false,
        severity: DoctorCheckSeverity.warning,
        detail: '未设置 SHOREBIRD_TOKEN，且已跳过 whoami（--skip-network）',
        fix: 'CI 请配置 SHOREBIRD_TOKEN；本机可去掉 --skip-network 再测登录态',
      );
    }

    return _whoamiCheck(
      okDetailPrefix: '已登录',
      okDetailSuffix: '（CI 建议改用 SHOREBIRD_TOKEN）',
      failDetailPrefix: '未设置 SHOREBIRD_TOKEN，且 shorebird account whoami 失败',
      failFix: 'Jenkins: 配置 SHOREBIRD_TOKEN=sb_api_...\n'
          '本机: shorebird login',
      failUsesGenericMessage: true,
    );
  }

  Future<DoctorCheckItem> _whoamiCheck({
    required String okDetailPrefix,
    String okDetailSuffix = '',
    required String failDetailPrefix,
    required String failFix,
    bool failUsesGenericMessage = false,
  }) async {
    try {
      final env = shorebirdCliEnvironment(environment);
      final result = await Process.run(
        'shorebird',
        ['account', 'whoami'],
        environment: env,
        runInShell: false,
      ).timeout(const Duration(seconds: 20));
      if (result.exitCode != 0) {
        final err = '${result.stderr}\n${result.stdout}'.trim();
        throw Exception(err.isEmpty ? 'exit ${result.exitCode}' : err);
      }
      final who = result.stdout.toString().trim().split('\n').firstWhere(
            (l) => l.trim().isNotEmpty,
            orElse: () => 'authenticated',
          );
      return DoctorCheckItem(
        id: 'shorebird_auth',
        title: 'Shorebird 鉴权',
        ok: true,
        severity: DoctorCheckSeverity.info,
        detail: '$okDetailPrefix · $who$okDetailSuffix',
      );
    } catch (e) {
      return DoctorCheckItem(
        id: 'shorebird_auth',
        title: 'Shorebird 鉴权',
        ok: false,
        severity: DoctorCheckSeverity.error,
        detail: failUsesGenericMessage
            ? failDetailPrefix
            : '$failDetailPrefix: $e',
        fix: failFix,
      );
    }
  }

  Future<List<DoctorCheckItem>> _checkNetwork() async {
    return [
      await _probeUrl(
        id: 'network_api',
        title: '连通 api.shorebird.dev',
        url: kShorebirdOfficialHostedUrl,
        fix: '打包机需能访问 Shorebird Console API。'
            '若公司代理/防火墙拦截，请放行 https://api.shorebird.dev\n'
            '（与设备 OTA 的 base_url / META_OTA_API 不是同一地址）',
      ),
      await _probeUrl(
        id: 'network_download',
        title: '连通 download.shorebird.dev',
        url: kShorebirdFlutterStorageBaseUrl,
        fix: '打包机需能下载 Shorebird Flutter 引擎。'
            '请放行 https://download.shorebird.dev\n'
            '首次 release 会拉引擎，网络不通会拖到打包末尾才失败',
      ),
    ];
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

    if (hosted.isNotEmpty &&
        !_sameHost(hosted, kShorebirdOfficialHostedUrl) &&
        !_looksLikeShorebirdOfficial(hosted)) {
      notes.add(
        '环境变量 SHOREBIRD_HOSTED_URL=$hosted '
        '疑似 OTA 地址；metax 出包时会强制覆盖为 '
        '$kShorebirdOfficialHostedUrl',
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
            : '当前 env 可被 metax 安全覆盖 '
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
      fix: '设备 OTA 用 shorebird.yaml base_url / META_OTA_API；'
          '不要把 OTA 地址赋给 SHOREBIRD_HOSTED_URL',
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

bool _looksLikeShorebirdToken(String token) {
  final t = token.trim();
  if (t.startsWith('sb_api_')) return true;
  // 兼容历史 CI token（较长 base64 类）
  if (t.length >= 20 && !t.contains(' ')) return true;
  return false;
}

bool _looksLikeShorebirdOfficial(String url) {
  final lower = url.toLowerCase();
  return lower.contains('api.shorebird.dev') ||
      lower.contains('console.shorebird.dev');
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
