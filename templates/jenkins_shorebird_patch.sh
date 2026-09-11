#!/usr/bin/env bash
# Jenkins：Shorebird 热更补丁
# 参数：
#   PLATFORM / platform   android | ios
#   RELEASE / release     如 3.4.100(1788746134)  （Active Choices 展示格式）
#   BRANCH / branch       可选，Flutter / Melos 分支
#   APP_DIR / app_dir     meta_app 工程根（其下须有 metaapp_flutter/）
#                         优先于 Jenkins 内置 WORKSPACE；未设时回退 WORKSPACE_DIR / WORKSPACE / pwd
# 兼容旧参数：VERSION + BUILD（若仍传入且无 RELEASE，则直接使用）
#
# FORCE_PATCH=true|1 时透传 --force-patch（跳过多仓库热更预审）
#
# 还需：FLUTTERPATCH_TOKEN, APPWRITE_* 等（见 jenkins_shorebird.env.example）
#
# 用法（Execute shell）：
#   export APP_DIR=/path/to/meta_app   # 含 metaapp_flutter 的仓库根
#   bash /path/to/metax/templates/jenkins_shorebird_patch.sh

set -euo pipefail

# ---- 参数映射 ----
BRANCH="${BRANCH:-${branch:-${FLUTTER_BRANCH:-}}}"
PLATFORM="${PLATFORM:-${platform:-}}"
RELEASE="${RELEASE:-${release:-}}"
VERSION="${VERSION:-${version:-${BUILD_NAME:-${buildName:-}}}}"
BUILD="${BUILD:-${build:-}}"   # 不要用 Jenkins 内置 BUILD_NUMBER 顶替业务 build

METAX_BIN="${METAX_BIN:-metax}"
FORCE_PATCH="${FORCE_PATCH:-false}"
ALLOW_ASSET_DIFFS="${ALLOW_ASSET_DIFFS:-false}"
# 工程根：APP_DIR 优先，避免误用 Jenkins 空 WORKSPACE
APP_DIR="${APP_DIR:-${app_dir:-${WORKSPACE_DIR:-${WORKSPACE:-$(pwd)}}}}"

# ---- 从 RELEASE 解析 VERSION / BUILD ----
# 支持：3.4.100(1788746134)  或  3.4.100+1788746134  或  3.4.100#1788746134
parse_release() {
  local raw="$1"
  raw="$(echo "${raw}" | sed 's/&#43;/+/g; s/[[:space:]]//g')"
  if [[ "${raw}" =~ ^([0-9]+\.[0-9]+\.[0-9]+)\(([0-9]+)\)$ ]]; then
    VERSION="${BASH_REMATCH[1]}"
    BUILD="${BASH_REMATCH[2]}"
  elif [[ "${raw}" =~ ^([0-9]+\.[0-9]+\.[0-9]+)[+#]([0-9]+)$ ]]; then
    VERSION="${BASH_REMATCH[1]}"
    BUILD="${BASH_REMATCH[2]}"
  else
    echo "ERROR: RELEASE 格式无法解析: ${raw}（期望 3.4.100(1788746134)）" >&2
    exit 1
  fi
}

if [[ -n "${RELEASE}" ]]; then
  parse_release "${RELEASE}"
fi

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
  echo "ERROR: 缺少 RELEASE（或旧参数 VERSION+BUILD）" >&2
  exit 1
fi

RELEASE_VERSION="${VERSION}+${BUILD}"

if [[ ! -d "${APP_DIR}" ]]; then
  echo "ERROR: APP_DIR 不存在: ${APP_DIR}" >&2
  exit 1
fi
if [[ ! -d "${APP_DIR}/metaapp_flutter" ]]; then
  echo "ERROR: APP_DIR 下缺少 metaapp_flutter/: ${APP_DIR}" >&2
  echo "       请 export APP_DIR=meta_app 仓库根（不要用 Jenkins WORKSPACE 空目录）" >&2
  exit 1
fi

echo "==> platform=${PLATFORM}"
echo "==> branch=${BRANCH:-"(当前分支，不切换)"}"
echo "==> release=${RELEASE:-"(from VERSION+BUILD)"}"
echo "==> release-version=${RELEASE_VERSION}"
echo "==> force-patch=${FORCE_PATCH}"
echo "==> app-dir=${APP_DIR}"

cd "${APP_DIR}"

# ---- 组装 metax patch 命令 ----
ARGS=(
  --workspace "${APP_DIR}"
  patch "${PLATFORM}"
  --release-version "${RELEASE_VERSION}"
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
