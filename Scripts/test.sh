#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH=""
SKIP_BUILD=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app)
      APP_PATH="$2"
      shift 2
      ;;
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

cd "${ROOT_DIR}"

if [[ "${SKIP_BUILD}" -eq 0 ]]; then
  python3 "${ROOT_DIR}/Scripts/generate_icon_assets.py"
  iconutil -c icns "${ROOT_DIR}/Resources/SnapMarkIcon.iconset" -o "${ROOT_DIR}/Resources/SnapMarkIcon.icns"
  swift build
fi

if [[ -n "${APP_PATH}" ]]; then
  python3 "${ROOT_DIR}/Tests/run_functional_tests.py" --root "${ROOT_DIR}" --app "${APP_PATH}"
else
  python3 "${ROOT_DIR}/Tests/run_functional_tests.py" --root "${ROOT_DIR}"
fi
