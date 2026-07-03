#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-debug}"
swift build -c "$CONFIG"

APP="build/SnapScreen.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp ".build/$CONFIG/SnapScreen" "$APP/Contents/MacOS/SnapScreen"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# ad-hoc 서명: TCC 권한 부여에 필요. 재빌드 시 권한 재요청이 필요할 수 있음(알려진 제약)
codesign --force --sign - "$APP"
echo "OK: $APP"
