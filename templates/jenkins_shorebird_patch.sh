#!/usr/bin/env bash
# Jenkins：Shorebird 热更补丁
# 依赖 Job 参数/环境变量：分支、平台、版本、build
#
# 建议参数名（可按你们 Jenkins 实际名改下面映射）：
#   BRANCH / branch          Flutter 分支
#   PLATFORM / platform      android | ios
#   VERSION / version        版本名，如 3.4.100
#   BUILD / build            buildNumber，如 1788397052
#
# 还需已配置（见 jenkins_shorebird.env.example）：
#   SHOREBIRD_TOKEN, META_OTA_API, META_OTA_TOKEN
#   APPWRITE_*（热更预审；跳过则加 FORCE_PATCH=true）
#
# 用法（Execute shell）：
#   bash /path/to/metax/templates/jenkins_shorebird_patch.sh
# 或把本脚本内容贴进 job。

set -euo pipefail

# ---- 参数映射（按你们 Jenkins 实际变量名调整左侧优先顺序）----
BRANCH="${BRANCH:-${branch:-${FLUTTER_BRANCH:-}}}"
PLATFORM="${PLATFORM:-${platform:-}}"
VERSION="${VERSION:-${version:-${BUILD_NAME:-${buildName:-}}}}"
BUILD="${BUILD:-${build:-${BUILD_NUMBER:-${buildNumber:-}}}}"

METAX_BIN="${METAX_BIN:-metax}"
FORCE_PATCH="${FORCE_PATCH:-false}"
ALLOW_ASSET_DIFFS="${ALLOW_ASSET_DIFFS:-false}"
CHANNEL="${CHANNEL:-${META_OTA_CHANNEL:-stable}}"

# ---- 校验 ----
if [[ -z "${PLATFORM}" ]]; then
  echo "ERROR: 缺少 PLATFORM（android|ios）" >&2
  exit 1
fi
PLATFORM="$(echo "${PLATFORM}" | tr '[:upper:]' '[:lower:]')"
case "${PLATFORM}" in
  android|ios) ;;
  *)
    echo "ERROR: PLATFORM 必须是 android 或 ios，当前=${PLATFORM}" >&2
    exit 1
    ;;
esac

if [[ -z "${VERSION}" || -z "${BUILD}" ]]; then
  echo "ERROR: 缺少 VERSION 或 BUILD（拼 release-version=VERSION+BUILD）" >&2
  exit 1
fi

RELEASE_VERSION="${VERSION}+${BUILD}"

echo "==> platform=${PLATFORM}"
echo "==> branch=${BRANCH:-"(当前分支，不切换)"}"
echo "==> release-version=${RELEASE_VERSION}"
echo "==> channel=${CHANNEL}"

# ---- 组装 metax 命令 ----
ARGS=(
  patch "${PLATFORM}"
  --release-version "${RELEASE_VERSION}"
  --channel "${CHANNEL}"
)

if [[ -n "${BRANCH}" ]]; then
  ARGS+=(--branch "${BRANCH}")
fi

if [[ "${FORCE_PATCH}" == "true" || "${FORCE_PATCH}" == "1" ]]; then
  ARGS+=(--force-patch)
fi

if [[ "${ALLOW_ASSET_DIFFS}" == "true" || "${ALLOW_ASSET_DIFFS}" == "1" ]]; then
  ARGS+=(--allow-asset-diffs)
fi

echo "==> 执行: ${METAX_BIN} ${ARGS[*]}"
exec "${METAX_BIN}" "${ARGS[@]}"
