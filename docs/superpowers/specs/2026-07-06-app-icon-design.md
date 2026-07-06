# SnapScreen 앱 아이콘 설계 문서

- 날짜: 2026-07-06
- 상태: 승인됨 (브레인스토밍 완료)
- 대상 릴리스: v0.6.0

## 1. 배경

SnapScreen은 현재 전용 앱 아이콘이 없어 macOS 기본 아이콘으로 표시된다(`.icns` 없음, `Info.plist`에 아이콘 키 없음, `bundle.sh`에 아이콘 처리 없음). 홈 창·Dock·Finder·시스템 설정 목록에서 정체성이 드러나지 않는다. 브랜드감을 주는 트렌디한 아이콘을 제작해 번들에 통합한다.

브레인스토밍에서 8개 모티프(렌즈/캡처프레임/크롭/주석/레터마크/번개/스택/크로스헤어)를 시각 비교한 뒤 **캡처 스택**을 선택, 이어서 색·심볼·마감을 단계적으로 확정했다.

## 2. 확정 디자인

- **모티프**: 겹쳐진 스크린샷 카드 스택 (깊이감으로 "여러 캡처"를 상징, 향후 갤러리 확장과도 연결)
- **배경**: 둥근 사각(squircle 근사, `rx=114` = 512의 22.3%) + 바이올렛 대각 그라디언트 `#6a5cff → #a638ff` + 상단 광택(흰색 0.28 → 투명)
- **스택**: 흰색 카드 3장, `-12°` 회전, 뒤 카드일수록 불투명도 낮게(0.3 / 0.55 / 1.0), 카드마다 부드러운 드롭섀도(깊이)
- **심볼**: 맨 위 카드 안에 캡처 프레임 코너 브래킷 4개(바이올렛 `#7a4cff` 선, 굵기 18)
- **캔버스**: 512×512 viewBox 기준 좌표 (실제 렌더는 배수 스케일)

확정 SVG 소스 (구현 시 `Resources/AppIcon.svg`로 저장):

```svg
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="512" height="512">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#6a5cff"/><stop offset="1" stop-color="#a638ff"/>
    </linearGradient>
    <linearGradient id="gloss" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#fff" stop-opacity="0.28"/>
      <stop offset="0.5" stop-color="#fff" stop-opacity="0"/>
    </linearGradient>
    <filter id="card" x="-30%" y="-30%" width="160%" height="160%">
      <feDropShadow dx="0" dy="10" stdDeviation="14" flood-color="#2a0a4a" flood-opacity="0.35"/>
    </filter>
    <filter id="soft" x="-30%" y="-30%" width="160%" height="160%">
      <feDropShadow dx="0" dy="6" stdDeviation="8" flood-color="#2a0a4a" flood-opacity="0.28"/>
    </filter>
  </defs>
  <rect width="512" height="512" rx="114" fill="url(#bg)"/>
  <rect width="512" height="512" rx="114" fill="url(#gloss)"/>
  <g transform="rotate(-12 256 256)">
    <rect x="150" y="150" width="212" height="212" rx="30" fill="#fff" opacity="0.3" filter="url(#soft)"/>
    <rect x="176" y="176" width="212" height="212" rx="30" fill="#fff" opacity="0.55" filter="url(#soft)"/>
    <rect x="128" y="128" width="212" height="212" rx="30" fill="#fff" filter="url(#card)"/>
    <g fill="none" stroke="#7a4cff" stroke-width="18" stroke-linecap="round" stroke-linejoin="round">
      <path d="M162 198 V178 A8 8 0 0 1 170 170 H190"/>
      <path d="M278 170 H298 A8 8 0 0 1 306 178 V198"/>
      <path d="M306 270 V290 A8 8 0 0 1 298 298 H278"/>
      <path d="M190 298 H170 A8 8 0 0 1 162 290 V270"/>
    </g>
  </g>
</svg>
```

## 3. 제작 파이프라인

이 환경에 필요한 도구가 모두 있음: `rsvg-convert`, `cairosvg`(SVG→PNG), `sips`, `iconutil`(아이콘 빌드).

`Scripts/make-icon.sh` (신규):
1. `Resources/AppIcon.svg`를 각 목표 픽셀 크기로 **직접** 래스터화(`rsvg-convert -w N -h N`) — 업스케일 대신 사이즈별 렌더로 선명도 확보
2. `.iconset` 디렉터리에 Apple 규격 파일명으로 배치:
   | 파일명 | px |
   |---|---|
   | icon_16x16.png | 16 |
   | icon_16x16@2x.png | 32 |
   | icon_32x32.png | 32 |
   | icon_32x32@2x.png | 64 |
   | icon_128x128.png | 128 |
   | icon_128x128@2x.png | 256 |
   | icon_256x256.png | 256 |
   | icon_256x256@2x.png | 512 |
   | icon_512x512.png | 512 |
   | icon_512x512@2x.png | 1024 |
3. `iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns`
4. 산출물 `Resources/AppIcon.icns`는 커밋한다(빌드 때마다 렌더 도구 의존 회피). SVG 소스도 함께 커밋해 재생성 가능하게 유지.

**렌더 폴백**: `rsvg-convert`가 `feDropShadow` 필터를 제대로 처리 못 하면 `cairosvg`로 대체(스크립트에서 우선순위 처리 또는 계획 단계에서 실제 렌더 확인 후 결정).

## 4. 작은 크기 가독성

16/32px에서 캡처 프레임 코너 브래킷이 뭉개질 수 있다. **계획 단계에서 실제 16/32px PNG를 렌더해 확인**하고:
- 충분히 또렷하면 단일 SVG로 진행
- 뭉개지면 작은 크기용 단순화 variant(`AppIcon-small.svg`: 심볼 제거 또는 프레임 선 굵게)를 만들어 16/32 슬롯에만 사용

이 판단은 구현 계획의 검증 스텝에 포함한다.

## 5. 번들 통합

- `Resources/Info.plist`: `CFBundleIconFile` = `AppIcon` 키 추가 (확장자 없이; macOS가 `.icns` 자동 해석)
- `Scripts/bundle.sh`: `Resources/AppIcon.icns` → `Contents/Resources/AppIcon.icns` 복사 스텝 추가 (기존 리소스 복사 패턴을 따름). 코드서명 전에 배치.
- 홈 창 등 앱 내부 UI에서 아이콘을 별도로 쓰지는 않는다(YAGNI) — 시스템 아이콘(Dock/Finder/전환기)만 대상.

## 6. 에러 처리

- `make-icon.sh`는 렌더/`iconutil` 실패 시 즉시 비영(非零) 종료(`set -euo pipefail`)하고 어떤 스텝에서 실패했는지 출력.
- `bundle.sh`는 `AppIcon.icns`가 없으면 경고 후 진행(아이콘 없이도 앱은 동작) — 하드 실패로 만들지 않는다.

## 7. 테스트 / 검증

아이콘은 시각물이라 단위 테스트 대상이 아니다. 검증은 다음으로 한다:
- **자동/기계 검증**: `make-icon.sh` 실행 후 `.icns` 생성 확인, `iconutil` 성공 종료, `sips -g pixelWidth Resources/AppIcon.icns`로 유효성, `bundle.sh` 후 `SnapScreen.app/Contents/Resources/AppIcon.icns` 존재 + 코드서명 통과(`codesign --verify`) 확인
- **수동**: `docs/manual-test-checklist.md`에 "14. 앱 아이콘" 섹션 — Finder/Dock/⌘Tab 전환기/시스템 설정 목록에서 새 아이콘 표시, 16px(메뉴바 인접)·큰 크기 모두 또렷한지, 다크/라이트 배경에서 확인

## 8. 버전

v0.6.0 — 새 비주얼 자산 추가(기능 추가급). `AppInfo.version` "0.6.0", `Info.plist` `CFBundleShortVersionString` "0.6.0", `CFBundleVersion` 8.
(직전 릴리스 v0.5.1 / build 7 기준. crop 버튼 색 완화 fix는 별도 브랜치로 선행 머지될 수 있으며, 그 경우에도 이 버전 범프는 유효하다.)
