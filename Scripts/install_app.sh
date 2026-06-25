#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_APP="${ROOT_DIR}/dist/SnapMark.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
LEGACY_USER_APP="${HOME}/Applications/SnapMark.app"

if [[ -n "${SNAPMARK_INSTALL_PATH:-}" ]]; then
  INSTALL_APP="${SNAPMARK_INSTALL_PATH}"
elif [[ -w "/Applications" ]]; then
  INSTALL_APP="/Applications/SnapMark.app"
else
  INSTALL_APP="${HOME}/Applications/SnapMark.app"
fi

cd "${ROOT_DIR}"
"${ROOT_DIR}/Scripts/build_app.sh" >/dev/null

pkill -x SnapMark >/dev/null 2>&1 || true

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

echo "${INSTALL_APP}"
