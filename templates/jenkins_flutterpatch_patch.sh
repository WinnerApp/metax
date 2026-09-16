#!/usr/bin/env bash
# Jenkins：FlutterPatch 热更补丁
# 参数：
#   PLATFORM / platform   android | ios
#   RELEASE / release     如 3.4.100(1788746134)
#   BRANCH / branch       可选，Melos 分支（check-ota / patch 都会切）
#   APP_DIR / app_dir     meta_app 工程根
# 可选：
#   CHECK_ONLY=true|1     仅检测是否支持热更，写出 JSON 后退出（不打补丁）
#   FORCE_PATCH=true|1    跳过预检并透传 --force-patch（与 CHECK_ONLY 互斥）
#   WHITELIST=true|1      本补丁开启设备白名单（透传 --whitelist）
#   WHITELIST=false|0     显式全量放量（透传 --no-whitelist）
#   UNIQUE_IDS            白名单 client_id，逗号分隔（透传 --unique-ids）
#   ALLOW_ASSET_DIFFS     透传 --allow-asset-diffs
# 兼容旧参数：VERSION + BUILD
#
# 热更预检在 metax check-ota 内部：同步代码 → 授权 Flutter 目录 → flutterpatch check-ota
# 产物：
#   ${WORKSPACE}/${BUILD_ID}/unsupported-files.json
#   ${WORKSPACE}/${BUILD_ID}/supported-files.json
#   ${WORKSPACE}/${BUILD_ID}/supported-resources.json   # 全量+增量+不支持资源热更配置
#
# 还需：FLUTTERPATCH_TOKEN、APPWRITE_*（节点或下面 ENV_FILE）
# 需 metax 已支持：--check-only / --whitelist / --unique-ids / --resources-out

set -euo pipefail

BRANCH="${BRANCH:-${branch:-${FLUTTER_BRANCH:-}}}"
PLATFORM="${PLATFORM:-${platform:-}}"
RELEASE="${RELEASE:-${release:-}}"
VERSION="${VERSION:-${version:-${BUILD_NAME:-${buildName:-}}}}"
BUILD="${BUILD:-${build:-}}"

METAX_BIN="${METAX_BIN:-metax}"
FORCE_PATCH="${FORCE_PATCH:-false}"
CHECK_ONLY="${CHECK_ONLY:-false}"
ALLOW_ASSET_DIFFS="${ALLOW_ASSET_DIFFS:-false}"
WHITELIST="${WHITELIST:-}"
UNIQUE_IDS="${UNIQUE_IDS:-${unique_ids:-}}"

ENV_FILE="${ENV_FILE:-${HOME}/jenkins_shorebird.env}"
if [[ -f "${ENV_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
fi

JOB_DIR="${WORKSPACE_DIR:-${WORKSPACE:-$(pwd)}}"
APP_DIR="${APP_DIR:-${app_dir:-${JOB_DIR}}}"

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

if [[ -z "${APP_DIR}" ]]; then
  echo "ERROR: 缺少 APP_DIR" >&2
  exit 1
fi
if [[ ! -d "${APP_DIR}" ]]; then
  echo "ERROR: APP_DIR 不存在: ${APP_DIR}" >&2
  exit 1
fi

if [[ ("${CHECK_ONLY}" == "true" || "${CHECK_ONLY}" == "1") && \
      ("${FORCE_PATCH}" == "true" || "${FORCE_PATCH}" == "1") ]]; then
  echo "ERROR: CHECK_ONLY 与 FORCE_PATCH 不能同时开启" >&2
  exit 1
fi

OUT_DIR="${JOB_DIR}/${BUILD_ID:-${BUILD_NUMBER:-manual}}"
mkdir -p "${OUT_DIR}"
UNSUPPORTED_JSON="${OUT_DIR}/unsupported-files.json"
SUPPORTED_JSON="${OUT_DIR}/supported-files.json"
RESOURCES_JSON="${OUT_DIR}/supported-resources.json"

echo "==> platform=${PLATFORM}"
echo "==> branch=${BRANCH:-"(当前分支，不切换)"}"
echo "==> release=${RELEASE:-"(from VERSION+BUILD)"}"
echo "==> release-version=${RELEASE_VERSION}"
echo "==> force-patch=${FORCE_PATCH}"
echo "==> check-only=${CHECK_ONLY}"
echo "==> whitelist=${WHITELIST:-"(未指定)"}"
echo "==> unique-ids=${UNIQUE_IDS:-"(无)"}"
echo "==> job-dir=${JOB_DIR}"
echo "==> app-dir=${APP_DIR}"
echo "==> out-dir=${OUT_DIR}"

cd "${APP_DIR}"

if [[ "${FORCE_PATCH}" == "true" || "${FORCE_PATCH}" == "1" ]]; then
  echo "==> FORCE_PATCH 已开启，跳过 metax check-ota"
else
  CHECK_ARGS=(
    --workspace "${APP_DIR}"
    check-ota
    --platform "${PLATFORM}"
    --buildName "${VERSION}"
    --release-version "${RELEASE_VERSION}"
    --unsupported-out "${UNSUPPORTED_JSON}"
    --supported-out "${SUPPORTED_JSON}"
    --resources-out "${RESOURCES_JSON}"
  )
  if [[ -n "${BRANCH}" ]]; then
    CHECK_ARGS+=(--branch "${BRANCH}")
  fi
  echo "==> 热更检测: ${METAX_BIN} ${CHECK_ARGS[*]}"
  set +e
  "${METAX_BIN}" "${CHECK_ARGS[@]}"
  check_rc=$?
  set -e
  echo "==> unsupported JSON → ${UNSUPPORTED_JSON}"
  echo "==> supported JSON → ${SUPPORTED_JSON}"
  echo "==> resources JSON → ${RESOURCES_JSON}"
  if [[ "${CHECK_ONLY}" == "true" || "${CHECK_ONLY}" == "1" ]]; then
    echo "==> CHECK_ONLY：仅检测，退出码=${check_rc}"
    exit "${check_rc}"
  fi
  if [[ "${check_rc}" -eq 2 ]]; then
    echo "ERROR: 当前工程相对 ${RELEASE_VERSION} 不支持热更，已中断。强行打补丁请设 FORCE_PATCH=true" >&2
    exit 2
  fi
  if [[ "${check_rc}" -ne 0 ]]; then
    echo "ERROR: metax check-ota 失败 exit=${check_rc}" >&2
    exit "${check_rc}"
  fi
  echo "==> 热更检测通过，继续打补丁"
fi

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

case "$(echo "${WHITELIST}" | tr '[:upper:]' '[:lower:]')" in
  true|1|yes)
    ARGS+=(--whitelist)
    ;;
  false|0|no)
    ARGS+=(--no-whitelist)
    ;;
esac

if [[ -n "${UNIQUE_IDS}" ]]; then
  ARGS+=(--unique-ids "${UNIQUE_IDS}")
  if [[ -z "${WHITELIST}" ]]; then
    ARGS+=(--whitelist)
  fi
fi

echo "==> 执行: ${METAX_BIN} ${ARGS[*]}"
exec "${METAX_BIN}" "${ARGS[@]}"
