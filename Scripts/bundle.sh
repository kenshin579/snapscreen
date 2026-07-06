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

# SwiftPM 리소스 번들 복사 (예: KeyboardShortcuts_KeyboardShortcuts.bundle).
# 이게 없으면 리소스를 가진 의존성이 Bundle.module 접근 시 fatalError로 크래시한다
# (설정 창의 KeyboardShortcuts.Recorder). 로컬 개발 빌드는 accessor가 .build 절대경로로
# 우연히 찾아 넘어가므로 재현되지 않지만, 배포된 zip에는 .build가 없어 반드시 크래시한다.
#
# 배치가 까다롭다: swift build가 생성한 accessor는 `Bundle.main.bundleURL/<번들명>`,
# 즉 .app 루트 바로 아래를 본다(실행 파일이 Contents/MacOS에 있어 Bundle.main이 .app으로
# 잡히기 때문). 그런데 .app 루트에 실제 파일을 두면 codesign이 "unsealed contents"로 실패한다.
# 해법: 실체는 규약 위치인 Contents/Resources에 두어 codesign 대상이 되게 하고,
# 서명이 끝난 뒤 루트에 상대 심링크를 만들어 accessor가 따라가게 한다.
mkdir -p "$APP/Contents/Resources"

# 앱 아이콘 (codesign 전에 배치해야 서명에 포함된다). 없으면 경고만 (아이콘 없이도 동작).
if [ -f Resources/AppIcon.icns ]; then
    cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
else
    echo "WARN: Resources/AppIcon.icns 없음 — 기본 아이콘으로 빌드됩니다" >&2
fi

for bundle in ".build/$CONFIG"/*.bundle; do
    [ -e "$bundle" ] && cp -R "$bundle" "$APP/Contents/Resources/"
done

# ad-hoc 서명: TCC 권한 부여에 필요. (심링크 생성 전에 서명해야 루트가 unsealed 되지 않는다.)
# 주의: 코드가 바뀔 때마다 cdhash가 달라져 화면 기록 권한을 다시 켜야 할 수 있고,
# 시스템 설정 > 화면 기록에 SnapScreen 항목이 중복 누적될 수 있다 (오래된 항목은 수동 삭제).
codesign --force --sign - "$APP"

# 서명 후 루트 심링크: accessor의 Bundle.main.bundleURL/<번들명> 탐색을 Contents/Resources로 연결.
# 서명 이후에 추가하므로 codesign 무결성(실행 파일 cdhash)은 유지된다.
for bundle in "$APP/Contents/Resources"/*.bundle; do
    [ -e "$bundle" ] || continue
    name="$(basename "$bundle")"
    ( cd "$APP" && ln -sf "Contents/Resources/$name" "$name" )
    # 배포 크래시 재발 방지 가드: 심링크가 실제 번들을 가리키는지 확인
    if [ ! -d "$APP/$name" ]; then
        echo "ERROR: 리소스 번들 심링크 $name 이(가) 유효하지 않습니다" >&2
        exit 1
    fi
done

echo "OK: $APP"
