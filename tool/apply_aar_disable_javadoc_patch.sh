#!/usr/bin/env bash
# 给 Flutter / Shorebird(FlutterPatch) SDK 关闭 `flutter build aar` 生成 Javadoc。
#
# 官方 aar_init_script.gradle 在 publishing.singleVariant 里调用 withJavadocJar()，
# 部分插件（如 amap_flutter_location）的 Dokka/Javadoc 任务会失败，拖慢或阻断打包。
# 本补丁：注释掉 withJavadocJar()，保留 withSourcesJar()。
#
# 用法:
#   ./tool/apply_aar_disable_javadoc_patch.sh
#   ./tool/apply_aar_disable_javadoc_patch.sh /path/to/flutter
#
# flutterpatch upgrade / 换引擎后请重跑。

set -euo pipefail

TARGET_REL="packages/flutter_tools/gradle/aar_init_script.gradle"
MARKER="Skip Javadoc/Dokka"

already_patched() {
  # 无活跃 withJavadocJar() 且带 marker，或整段 afterProject 已被注释
  local f="$1"
  if grep -qE '^[[:space:]]*withJavadocJar\(\)' "$f" 2>/dev/null; then
    return 1
  fi
  grep -q "$MARKER" "$f" 2>/dev/null && return 0
  # speedUpFlutterAarBuild 整段注释 afterProject 的也算已关闭
  grep -qE '^//[[:space:]]*afterProject' "$f" 2>/dev/null
}

apply_to_file() {
  local target="$1"
  python3 - "$target" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
marker = "Skip Javadoc/Dokka"
if "withJavadocJar()" not in text:
    sys.exit(0)
# 已有 marker 且无活跃调用 → 幂等
active = any(
    line.lstrip().startswith("withJavadocJar()") and not line.lstrip().startswith("//")
    for line in text.splitlines()
)
if not active and marker in text:
    sys.exit(0)

# 仅替换未注释的 withJavadocJar() 行（保留缩进）
lines = text.splitlines(keepends=True)
out = []
i = 0
changed = 0
while i < len(lines):
    line = lines[i]
    stripped = line.lstrip()
    indent = line[: len(line) - len(stripped)]
    if stripped.startswith("withJavadocJar()") and not stripped.startswith("//"):
        # 若上一行已是 marker 注释，只注释本行
        prev = out[-1] if out else ""
        if marker in prev:
            out.append(f"{indent}// withJavadocJar()\n" if line.endswith("\n") else f"{indent}// withJavadocJar()")
        else:
            block = (
                f"{indent}// {marker}: fails on plugins like amap_flutter_location\n"
                f"{indent}// (javaDocReleaseGeneration / DokkaWorkAction).\n"
                f"{indent}// withJavadocJar()"
            )
            out.append(block + ("\n" if line.endswith("\n") else ""))
        changed += 1
        i += 1
        continue
    out.append(line)
    i += 1

if changed == 0:
    sys.exit(2)

path.write_text("".join(out), encoding="utf-8")
print(f"patched {changed} withJavadocJar() call(s)", file=sys.stderr)
PY
}

apply_to_root() {
  local root="$1"
  local target="$root/$TARGET_REL"
  if [[ ! -f "$target" ]]; then
    echo "跳过（无目标文件）: $root"
    return 0
  fi
  if already_patched "$target"; then
    echo "已关闭 Javadoc: $root"
    return 0
  fi

  echo "关闭 AAR Javadoc: $root"
  if ! apply_to_file "$target"; then
    echo "警告: 未能注释 withJavadocJar(): $target" >&2
    return 1
  fi
  if ! already_patched "$target"; then
    echo "警告: 打补丁后仍检测到活跃 withJavadocJar(): $target" >&2
    return 1
  fi
  echo "完成: $root"
}

discover_roots() {
  local home="${HOME:-}"
  if [[ $# -gt 0 ]]; then
    printf '%s\n' "$@"
    return
  fi

  local found=0
  if [[ -d "$home/.flutterpatch/bin/cache/flutter" ]]; then
    while IFS= read -r d; do
      [[ -f "$d/$TARGET_REL" ]] || continue
      echo "$d"
      found=1
    done < <(find "$home/.flutterpatch/bin/cache/flutter" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort)
  fi

  if [[ -d "$home/fvm/versions" ]]; then
    while IFS= read -r d; do
      [[ -f "$d/$TARGET_REL" ]] || continue
      echo "$d"
      found=1
    done < <(find "$home/fvm/versions" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort)
  fi

  # 常见 FLUTTER_ROOT / PATH 中的 flutter
  local flutter_bin
  flutter_bin="$(command -v flutter 2>/dev/null || true)"
  if [[ -n "$flutter_bin" ]]; then
    local flutter_root
    flutter_root="$(cd "$(dirname "$flutter_bin")/.." && pwd)"
    if [[ -f "$flutter_root/$TARGET_REL" ]]; then
      echo "$flutter_root"
      found=1
    fi
  fi

  if [[ "$found" -eq 0 ]]; then
    echo "未发现 Flutter SDK，请传入路径" >&2
    exit 1
  fi
}

while IFS= read -r root; do
  [[ -z "$root" ]] && continue
  if ! apply_to_root "$root"; then
    echo "警告: 跳过失败的 SDK: $root" >&2
  fi
done < <(discover_roots "$@")

echo "全部完成。验证示例:"
echo "  grep -n withJavadocJar ~/.flutterpatch/bin/cache/flutter/*/packages/flutter_tools/gradle/aar_init_script.gradle"
