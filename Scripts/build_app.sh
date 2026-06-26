#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="${ROOT_DIR}/dist/SnapMark.app"
EXECUTABLE="${ROOT_DIR}/.build/release/SnapMark"
INFO_PLIST="${ROOT_DIR}/Resources/Info.plist"
VERSION_FILE="${ROOT_DIR}/Resources/Version.env"
PLIST_BUDDY="/usr/libexec/PlistBuddy"
LAUNCH_AFTER_BUILD="${SNAPMARK_LAUNCH_AFTER_BUILD:-1}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-launch)
      LAUNCH_AFTER_BUILD=0
      shift
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

read_version_value() {
  local key="$1"
  awk -F= -v key="${key}" '$1 == key { print $2 }' "${VERSION_FILE}" | tail -n 1
}

bump_app_version() {
  local major minor next_minor mmdd version tmp

  if [[ ! -f "${VERSION_FILE}" ]]; then
    printf 'SNAPMARK_MAJOR=1\nSNAPMARK_MINOR=0\n' >"${VERSION_FILE}"
  fi

  major="$(read_version_value "SNAPMARK_MAJOR")"
  minor="$(read_version_value "SNAPMARK_MINOR")"

  if [[ ! "${major}" =~ ^[0-9]+$ ]]; then
    echo "invalid SNAPMARK_MAJOR in ${VERSION_FILE}: ${major}" >&2
    exit 2
  fi

  if [[ ! "${minor}" =~ ^[0-9]+$ ]]; then
    echo "invalid SNAPMARK_MINOR in ${VERSION_FILE}: ${minor}" >&2
    exit 2
  fi

  next_minor=$((minor + 1))
  mmdd="$(date +%m%d)"
  version="${major}.${next_minor}.${mmdd}"

  tmp="$(mktemp "${VERSION_FILE}.XXXXXX")"
  printf 'SNAPMARK_MAJOR=%s\nSNAPMARK_MINOR=%s\n' "${major}" "${next_minor}" >"${tmp}"
  mv "${tmp}" "${VERSION_FILE}"

  "${PLIST_BUDDY}" -c "Set :CFBundleShortVersionString ${version}" "${INFO_PLIST}"
  "${PLIST_BUDDY}" -c "Set :CFBundleVersion ${version}" "${INFO_PLIST}"

  printf '%s' "${version}"
}

cd "${ROOT_DIR}"
python3 "${ROOT_DIR}/Scripts/generate_icon_assets.py"
rm -f "${ROOT_DIR}/Resources/SnapMarkIcon.icns"
iconutil -c icns "${ROOT_DIR}/Resources/SnapMarkIcon.iconset" -o "${ROOT_DIR}/Resources/SnapMarkIcon.icns"
swift build -c release
APP_VERSION="$(bump_app_version)"
echo "version: ${APP_VERSION}" >&2

rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

cp "${EXECUTABLE}" "${APP_DIR}/Contents/MacOS/SnapMark"
cp "${INFO_PLIST}" "${APP_DIR}/Contents/Info.plist"
cp "${ROOT_DIR}/Resources/SnapMarkIcon.icns" "${APP_DIR}/Contents/Resources/SnapMarkIcon.icns"
cp "${ROOT_DIR}/Resources/StatusIcon.png" "${APP_DIR}/Contents/Resources/StatusIcon.png"
chmod +x "${APP_DIR}/Contents/MacOS/SnapMark"

CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:-}"

if [[ -z "${CODE_SIGN_IDENTITY}" ]]; then
  CODE_SIGN_IDENTITY="$(
    security find-identity -v -p codesigning 2>/dev/null \
      | sed -n 's/.*"\(Apple Development: [^"]*\)".*/\1/p' \
      | head -n 1
  )"
fi

if [[ -z "${CODE_SIGN_IDENTITY}" ]]; then
  echo "warning: no Apple Development signing identity found; using ad-hoc signing." >&2
  echo "warning: macOS Screen Recording permission may need to be granted again after rebuilds." >&2
  codesign --force --sign - "${APP_DIR}" >/dev/null
else
  codesign --force --deep --sign "${CODE_SIGN_IDENTITY}" "${APP_DIR}" >/dev/null
  echo "signed with: ${CODE_SIGN_IDENTITY}" >&2
fi

"${ROOT_DIR}/Scripts/test.sh" --skip-build --app "${APP_DIR}"

if [[ "${LAUNCH_AFTER_BUILD}" -eq 1 ]]; then
  "${ROOT_DIR}/Scripts/install_app.sh" --skip-build
else
  echo "${APP_DIR}"
fi
