#!/usr/bin/env bash

set -euo pipefail

dart_tool_dir=$PWD/.dart_tool
if [ -d "$dart_tool_dir" ]; then
  rm -rf "$dart_tool_dir"
fi
dart pub global deactivate meta_tool 2>/dev/null || true
dart pub global activate -s path .

# 本机 alias 指向 ~/.local/bin/metax（AOT），需同步编译，否则仍跑旧二进制
mkdir -p "$HOME/.local/bin"
dart compile exe -o "$HOME/.local/bin/metax" bin/metax.dart
echo "已安装: $HOME/.local/bin/metax"

# 可选：给 FlutterPatch 3.41.9 / FVM 3.41.9 打 ios-framework 仅真机补丁
if [[ "${APPLY_IOS_FRAMEWORK_DEVICE_ONLY_PATCH:-1}" == "1" ]]; then
  bash "$(dirname "$0")/tool/apply_ios_framework_device_only_patch.sh" || true
fi
