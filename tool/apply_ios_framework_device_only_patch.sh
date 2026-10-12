#!/usr/bin/env bash
# 给 Flutter / Shorebird(FlutterPatch) SDK 打「ios-framework 默认只编真机」补丁。
#
# 官方 ios-framework 会额外编 iphonesimulator（插件还强制 Debug），且 SYMROOT
# 落在每次清空的 output 目录 → 比 Android 二次打包慢很多。
# 本补丁：默认 --no-simulator，插件 Xcode 产物改到 build/ios/framework_xcode_cache。
#
# 用法:
#   ./tool/apply_ios_framework_device_only_patch.sh
#   ./tool/apply_ios_framework_device_only_patch.sh /path/to/flutter
#
# flutterpatch upgrade / 换引擎后请重跑。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PATCH_FILE="$SCRIPT_DIR/ios_framework_device_only.patch"
TARGET_REL="packages/flutter_tools/lib/src/commands/build_ios_framework.dart"

invalidate_tools() {
  local root="$1"
  rm -f "$root/bin/cache/flutter_tools.stamp" "$root/bin/cache/flutter_tools.snapshot"
}

already_patched() {
  grep -q "Also produce iphonesimulator slices" "$1" 2>/dev/null
}

has_absolute_symroot() {
  # xcodebuild cwd=Pods；相对 SYMROOT 会写到 ios/Pods/build/... 导致 listSync 崩溃
  grep -q "path.absolute" "$1" 2>/dev/null && grep -q "framework_xcode_cache" "$1" 2>/dev/null
}

# 修复已打补丁但 SYMROOT 仍为相对路径的旧版本
fixup_absolute_symroot() {
  local target="$1"
  already_patched "$target" || return 0
  has_absolute_symroot "$target" && return 0

  python3 - "$target" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text()
new_fn = """  Directory _pluginXcodeCache(XcodeSdk sdk) {
    return globals.fs.directory(
      globals.fs.path.absolute(
        globals.fs.path.join(
          getBuildDirectory(),
          'ios',
          'framework_xcode_cache',
          sdk.platformName,
        ),
      ),
    );
  }"""
pat = re.compile(
    r"  Directory _pluginXcodeCache\(XcodeSdk sdk\) \{\n"
    r"    return globals\.fs\n"
    r"        \.directory\(getBuildDirectory\(\)\)\n"
    r"        \.childDirectory\('ios'\)\n"
    r"        \.childDirectory\('framework_xcode_cache'\)\n"
    r"        \.childDirectory\(sdk\.platformName\);\n"
    r"  \}",
)
m = pat.search(text)
if not m:
    sys.exit(2)
path.write_text(text[: m.start()] + new_fn + text[m.end() :])
PY
  local rc=$?
  if [[ "$rc" -eq 0 ]]; then
    echo "已修复相对 SYMROOT → 绝对路径: $target"
    return 0
  fi
  echo "警告: 无法自动修复相对 SYMROOT: $target" >&2
  return 1
}

apply_to_root() {
  local root="$1"
  local target="$root/$TARGET_REL"
  if [[ ! -f "$target" ]]; then
    echo "跳过（无目标文件）: $root"
    return 0
  fi
  if already_patched "$target"; then
    echo "已打过补丁: $root"
    fixup_absolute_symroot "$target" || true
    invalidate_tools "$root"
    return 0
  fi

  echo "打补丁: $root"
  if ! (cd "$root" && git apply "$PATCH_FILE"); then
    echo "警告: git apply 失败（版本可能与补丁基线不一致）: $root" >&2
    return 1
  fi
  if ! already_patched "$target"; then
    echo "警告: 打补丁后未检测到标志位: $target" >&2
    return 1
  fi
  fixup_absolute_symroot "$target" || true
  invalidate_tools "$root"
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
      # 补丁基线是 FlutterPatch 3.41.9；用 --version 过滤，避免对 3.47 等误打
      ver="$("$d/bin/flutter" --version 2>/dev/null | head -1 || true)"
      if [[ "$ver" == *"3.41.9"* ]] || already_patched "$d/$TARGET_REL"; then
        echo "$d"
        found=1
      else
        echo "跳过非 3.41.9 FlutterPatch SDK: $d ($ver)" >&2
      fi
    done < <(find "$home/.flutterpatch/bin/cache/flutter" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort)
  fi

  if [[ -d "$home/fvm/versions/3.41.9" ]]; then
    echo "$home/fvm/versions/3.41.9"
    found=1
  fi

  if [[ "$found" -eq 0 ]]; then
    echo "未发现 Flutter SDK，请传入路径" >&2
    exit 1
  fi
}

if [[ ! -f "$PATCH_FILE" ]]; then
  echo "缺少补丁文件: $PATCH_FILE" >&2
  exit 1
fi

while IFS= read -r root; do
  [[ -z "$root" ]] && continue
  # 3.47 等新版本若 apply 失败则告警跳过，不中断其它 SDK
  if ! apply_to_root "$root"; then
    echo "警告: 跳过失败的 SDK: $root" >&2
  fi
done < <(discover_roots "$@")

echo "全部完成。验证示例:"
echo "  ~/.flutterpatch/bin/cache/flutter/*/bin/flutter build ios-framework -h | grep simulator"
