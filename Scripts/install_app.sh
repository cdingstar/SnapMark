#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_APP="${ROOT_DIR}/dist/SnapMark.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
LEGACY_USER_APP="${HOME}/Applications/SnapMark.app"
SKIP_BUILD=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-build)
      SKIP_BUILD=1
      shift
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

if [[ -n "${SNAPMARK_INSTALL_PATH:-}" ]]; then
  INSTALL_APP="${SNAPMARK_INSTALL_PATH}"
elif [[ -w "/Applications" ]]; then
  INSTALL_APP="/Applications/SnapMark.app"
else
  INSTALL_APP="${HOME}/Applications/SnapMark.app"
fi

cd "${ROOT_DIR}"
if [[ "${SKIP_BUILD}" -eq 0 ]]; then
  "${ROOT_DIR}/Scripts/build_app.sh" --no-launch >/dev/null
fi

pkill -x SnapMark >/dev/null 2>&1 || true
for _ in {1..30}; do
  if ! pgrep -x SnapMark >/dev/null 2>&1; then
    break
  fi
  sleep 0.1
done

if pgrep -x SnapMark >/dev/null 2>&1; then
  pkill -9 -x SnapMark >/dev/null 2>&1 || true
fi

if [[ ! -d "${SOURCE_APP}" ]]; then
  echo "missing built app: ${SOURCE_APP}" >&2
  exit 2
fi

mkdir -p "$(dirname "${INSTALL_APP}")"
rm -rf "${INSTALL_APP}"
ditto "${SOURCE_APP}" "${INSTALL_APP}"

if [[ "${INSTALL_APP}" != "${LEGACY_USER_APP}" && -d "${LEGACY_USER_APP}" ]]; then
  "${LSREGISTER}" -u "${LEGACY_USER_APP}" >/dev/null 2>&1 || true
  rm -rf "${LEGACY_USER_APP}"
fi

if [[ "${INSTALL_APP}" != "${SOURCE_APP}" ]]; then
  "${LSREGISTER}" -u "${SOURCE_APP}" >/dev/null 2>&1 || true
fi

"${LSREGISTER}" -f "${INSTALL_APP}" >/dev/null 2>&1 || true
open "${INSTALL_APP}"
for _ in {1..50}; do
  if pgrep -x SnapMark >/dev/null 2>&1; then
    break
  fi
  sleep 0.1
done

if ! pgrep -x SnapMark >/dev/null 2>&1; then
  echo "warning: SnapMark did not report a running process after open." >&2
fi

echo "${INSTALL_APP}"
