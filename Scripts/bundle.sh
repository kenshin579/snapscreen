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

# ad-hoc 서명: TCC 권한 부여에 필요.
# 주의: 코드가 바뀔 때마다 cdhash가 달라져 화면 기록 권한을 다시 켜야 할 수 있고,
# 시스템 설정 > 화면 기록에 SnapScreen 항목이 중복 누적될 수 있다 (오래된 항목은 수동 삭제).
codesign --force --sign - "$APP"
echo "OK: $APP"
