import 'dart:io';

/// 环境预检通用结果类型（Shorebird / metax doctor 共用）。
enum DoctorCheckSeverity {
  /// 阻断后续打包 / 上传 / 补丁
  error,

  /// 可能踩坑，默认不失败
  warning,

  /// 仅提示
  info,
}

class DoctorCheckItem {
  final String id;
  final String title;
  final bool ok;
  final DoctorCheckSeverity severity;
  final String detail;
  final String? fix;
  final String? group;

  const DoctorCheckItem({
    required this.id,
    required this.title,
    required this.ok,
    required this.severity,
    required this.detail,
    this.fix,
    this.group,
  });

  bool get isBlocking => !ok && severity == DoctorCheckSeverity.error;

  DoctorCheckItem copyWith({
    String? id,
    String? title,
    bool? ok,
    DoctorCheckSeverity? severity,
    String? detail,
    String? fix,
    String? group,
  }) {
    return DoctorCheckItem(
      id: id ?? this.id,
      title: title ?? this.title,
      ok: ok ?? this.ok,
      severity: severity ?? this.severity,
      detail: detail ?? this.detail,
      fix: fix ?? this.fix,
      group: group ?? this.group,
    );
  }
}

class DoctorReport {
  final List<DoctorCheckItem> items;

  const DoctorReport(this.items);

  List<DoctorCheckItem> get failures =>
      items.where((e) => e.isBlocking).toList();

  List<DoctorCheckItem> get warnings => items
      .where((e) => !e.ok && e.severity == DoctorCheckSeverity.warning)
      .toList();

  bool get ok => failures.isEmpty;
}

/// 静默探测 PATH 中的命令（不打 which 输出）。
Future<String?> whichCommand(
  String name, {
  Map<String, String>? environment,
}) async {
  try {
    final result = await Process.run(
      'which',
      [name],
      environment: environment,
      runInShell: false,
    );
    final path = result.stdout.toString().trim();
    if (result.exitCode == 0 && path.isNotEmpty) return path;
  } catch (_) {}
  return null;
}

DoctorCheckItem commandPresent({
  required String id,
  required String title,
  required String? path,
  required String fix,
  DoctorCheckSeverity missingSeverity = DoctorCheckSeverity.error,
  String? group,
}) {
  if (path != null && path.isNotEmpty) {
    return DoctorCheckItem(
      id: id,
      title: title,
      ok: true,
      severity: DoctorCheckSeverity.info,
      detail: path,
      group: group,
    );
  }
  return DoctorCheckItem(
    id: id,
    title: title,
    ok: false,
    severity: missingSeverity,
    detail: 'PATH 中未找到',
    fix: fix,
    group: group,
  );
}

DoctorCheckItem fileOrDirPresent({
  required String id,
  required String title,
  required bool exists,
  required String path,
  required String fix,
  DoctorCheckSeverity missingSeverity = DoctorCheckSeverity.error,
  String? group,
}) {
  if (exists) {
    return DoctorCheckItem(
      id: id,
      title: title,
      ok: true,
      severity: DoctorCheckSeverity.info,
      detail: path,
      group: group,
    );
  }
  return DoctorCheckItem(
    id: id,
    title: title,
    ok: false,
    severity: missingSeverity,
    detail: '不存在: $path',
    fix: fix,
    group: group,
  );
}

DoctorCheckItem envKeysPresent({
  required String id,
  required String title,
  required Map<String, String> env,
  required List<String> keys,
  required String fix,
  DoctorCheckSeverity missingSeverity = DoctorCheckSeverity.error,
  String? group,
}) {
  final missing = <String>[];
  final present = <String>[];
  for (final key in keys) {
    final v = (env[key] ?? '').trim();
    if (v.isEmpty) {
      missing.add(key);
    } else {
      present.add(key);
    }
  }
  if (missing.isEmpty) {
    return DoctorCheckItem(
      id: id,
      title: title,
      ok: true,
      severity: DoctorCheckSeverity.info,
      detail: present.join(', '),
      group: group,
    );
  }
  return DoctorCheckItem(
    id: id,
    title: title,
    ok: false,
    severity: missingSeverity,
    detail: '缺少: ${missing.join(', ')}'
        '${present.isEmpty ? '' : '；已有: ${present.join(', ')}'}',
    fix: fix,
    group: group,
  );
}
