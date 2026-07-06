#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

SVG="Resources/AppIcon.svg"
ICNS="Resources/AppIcon.icns"
ICONSET="build/AppIcon.iconset"

if [ ! -f "$SVG" ]; then
    echo "ERROR: $SVG 없음" >&2; exit 1
fi

# 렌더러: rsvg-convert 우선, 없으면 cairosvg 폴백.
render() {  # render <size> <out>
    local size="$1" out="$2"
    if command -v rsvg-convert >/dev/null 2>&1; then
        rsvg-convert -w "$size" -h "$size" "$SVG" -o "$out"
    elif command -v cairosvg >/dev/null 2>&1; then
        cairosvg "$SVG" -o "$out" --output-width "$size" --output-height "$size"
    else
        echo "ERROR: rsvg-convert 또는 cairosvg 필요" >&2; exit 1
    fi
}

rm -rf "$ICONSET"
mkdir -p "$ICONSET"

# Apple iconset 규격: 파일명 <- 픽셀크기
render 16   "$ICONSET/icon_16x16.png"
render 32   "$ICONSET/icon_16x16@2x.png"
render 32   "$ICONSET/icon_32x32.png"
render 64   "$ICONSET/icon_32x32@2x.png"
render 128  "$ICONSET/icon_128x128.png"
render 256  "$ICONSET/icon_128x128@2x.png"
render 256  "$ICONSET/icon_256x256.png"
render 512  "$ICONSET/icon_256x256@2x.png"
render 512  "$ICONSET/icon_512x512.png"
render 1024 "$ICONSET/icon_512x512@2x.png"

iconutil -c icns "$ICONSET" -o "$ICNS"
echo "OK: $ICNS"
