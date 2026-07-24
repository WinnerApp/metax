#!/usr/bin/env bash

dart_tool_dir=$PWD/.dart_tool
if [ -d "$dart_tool_dir" ];then
    rm -rf "$dart_tool_dir"
fi
dart pub global deactivate meta_tool 2>/dev/null || true
dart pub global activate -s path .