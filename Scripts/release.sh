#!/bin/bash
# 릴리스 태그를 검증 후 생성·푸시한다. 태그가 푸시되면 .github/workflows/release.yml이
# .app 번들을 빌드해 GitHub Release를 자동 생성한다.
#
# 사용법: Scripts/release.sh v0.1.0
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-}"

fail() { echo "ERROR: $1" >&2; exit 1; }

# 1. 버전 형식 검증 (vX.Y.Z)
[[ -n "$VERSION" ]] || fail "버전을 지정하세요. 예: make release VERSION=v0.1.0"
[[ "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "버전 형식이 잘못됐습니다 (vX.Y.Z): $VERSION"
BARE_VERSION="${VERSION#v}"

# 2. main 브랜치 + 클린 트리 + 원격과 동기화 확인
BRANCH=$(git branch --show-current)
[[ "$BRANCH" == "main" ]] || fail "main 브랜치에서만 릴리스할 수 있습니다 (현재: $BRANCH)"
[[ -z "$(git status --porcelain)" ]] || fail "커밋되지 않은 변경이 있습니다"
git fetch origin main --quiet
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || fail "로컬 main이 origin/main과 다릅니다 (git pull 필요)"

# 3. 중복 태그 확인
if git rev-parse "$VERSION" >/dev/null 2>&1; then
    fail "태그 $VERSION 이(가) 이미 존재합니다"
fi

# 4. 소스 버전 일치 확인 (Info.plist, AppInfo.swift)
PLIST_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
[[ "$PLIST_VERSION" == "$BARE_VERSION" ]] || \
    fail "Resources/Info.plist CFBundleShortVersionString($PLIST_VERSION)이 $BARE_VERSION 과 다릅니다"
grep -q "version = \"$BARE_VERSION\"" Sources/SnapScreenKit/Support/AppInfo.swift || \
    fail "AppInfo.version이 $BARE_VERSION 과 다릅니다 (Sources/SnapScreenKit/Support/AppInfo.swift)"

# 5. 테스트 + 릴리스 번들 빌드 확인
echo "==> swift test"
swift test
echo "==> Scripts/bundle.sh release"
Scripts/bundle.sh release

# 6. 태그 생성 + 푸시
git tag -a "$VERSION" -m "Release $VERSION"
git push origin "$VERSION"

echo ""
echo "OK: $VERSION 태그를 푸시했습니다."
echo "GitHub Actions가 Release를 생성합니다: https://github.com/kenshin579/snapscreen/actions"
