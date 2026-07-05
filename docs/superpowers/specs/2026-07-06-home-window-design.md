# 홈 창 설계 문서

- 날짜: 2026-07-06
- 상태: 승인됨 (브레인스토밍 완료)
- 대상 릴리스: v0.4.0

## 1. 배경

SnapScreen은 현재 순수 메뉴바 앱(LSUIElement/accessory)이라 실행해도 메뉴바 아이콘만 뜨고 앱 창이 없다. 사용자가 "실행하면 기본 앱 화면도 보이면 좋겠다"고 요청.

경쟁 앱 조사 결과: 대부분의 스크린샷 앱은 순수 메뉴바형이지만, 같은 OSS 포지션의 Snapzy·Capso는 메뉴바 상주를 유지하면서 홈 창을 추가했다(유형 B). SnapScreen도 이 진화 경로를 따른다. 홈 창 형태는 **런처/대시보드**(큰 캡처 버튼 3개)로 결정 — 기존 기능만으로 구현 가능하고, "무엇을 할 수 있는지" 발견성을 확보한다. (갤러리형은 히스토리 저장 기능이 선행되어야 해 범위가 커서 제외.)

## 2. 범위

- 앱 실행 시 **자동으로** 홈 창 표시
- 홈 창 구성: 캡처 버튼 3종(영역/창/전체, 각 버튼에 단축키 병기) + 하단 버전 표시
- 홈 창을 열면 독 아이콘 등장, 닫으면 사라지고 메뉴바 상주만 유지 (활성화 정책 토글)
- 메뉴바 메뉴에 "SnapScreen 홈…" 항목 추가 (닫은 홈 창 다시 열기)

**비목표**: 최근 캡처 갤러리/히스토리, 홈 창 내 설정(메뉴바 "설정…" 유지), 업데이트 상태 표시(설정 창·메뉴바에만), 저장 폴더 열기, "실행 시 자동 표시" 켜고 끄기 옵션(항상 표시)

## 3. 구성 요소

새 모듈 `Sources/SnapScreenKit/Home/` 2개 파일 + 활성화 정책 관리자:

| 파일 | 책임 |
|---|---|
| `Home/HomeWindowController.swift` | NSWindowController — SwiftUI HomeView를 NSHostingController로 감쌈, `isReleasedWhenClosed = false`, 고정 크기(리사이즈 불가), 창 닫힘 감지 |
| `Home/HomeView.swift` | SwiftUI — 캡처 버튼 3개(단축키 병기) + 하단 버전. 버튼이 `CaptureCoordinator.beginCapture(_:)` 호출 |
| `AppCore/ActivationPolicyManager.swift` | @MainActor — 표시 중인 앱 창 집합 추적, 집합이 비면 `.accessory` / 하나라도 있으면 `.regular` |

## 4. 활성화 정책 토글 (핵심 동작)

- 앱 시작(`applicationDidFinishLaunching`): 홈 창 표시 + `.regular` → 독 아이콘 등장, 창이 포커스/⌘Tab 정상
- 홈 창 닫기: `ActivationPolicyManager`가 "보이는 창 0개" 확인 시 `.accessory` → 독 아이콘 사라지고 메뉴바만
- 메뉴바 "SnapScreen 홈…": 창을 닫은 뒤 다시 열기 — `.regular` + `NSApp.activate`
- `applicationShouldTerminateAfterLastWindowClosed`는 false 유지(accessory 앱 기본) → 모든 창을 닫아도 메뉴바 상주 지속

**편집기 창과의 상호작용 규칙:** 편집기 창이 여러 개 떠 있을 때 홈 창만 닫아도 `.accessory`로 가면 안 된다. 규칙은 **"등록된 표시 창(홈+편집기+설정)이 하나도 없을 때만 `.accessory`"**. 홈·편집기·설정 창 모두 `ActivationPolicyManager`에 register/unregister한다. 단축키로만 캡처해 편집기가 떠도 독이 잠깐 보였다가 닫으면 사라지는 일관된 동작이 된다.

## 5. 데이터 흐름

```
앱 시작 (AppDelegate)
  → HomeWindowController 생성 + 표시 → policyManager.register(home) → .regular (독 등장)
  → HomeView 캡처 버튼 클릭 → coordinator.beginCapture(.area/.window/.fullScreen)
     (기존 흐름 그대로: 오버레이 → 편집기, 편집기도 policyManager에 register)
  → 홈 창 닫기 → policyManager.unregister(home) → 표시 창 0개면 .accessory (독 숨김)
  → 메뉴바 "SnapScreen 홈…" → HomeWindowController.show() → register → .regular
```

## 6. 통합 지점 (기존 코드 수정)

- `AppDelegate`: `homeWindowController`와 `activationPolicyManager` 보유. 시작 시 홈 창 표시. `updateState`와 동일한 소유 패턴.
- `StatusItemController`: 메뉴에 "SnapScreen 홈…" 항목 1개 추가 (기존 `openSettings`와 같은 클로저 주입 패턴)
- `CaptureCoordinator.beginCapture(_:)`는 이미 `public @MainActor` — HomeView에서 그대로 호출, 캡처 로직 변경 없음
- `EditorWindowController`/`SettingsWindowController`: 생성/닫힘 시 `ActivationPolicyManager`에 register/unregister 추가

## 7. 에러 처리

홈 창은 로컬 UI라 실패 지점이 적다. 캡처 버튼은 기존 `beginCapture`의 권한/실패 처리(Notifier 경로)를 그대로 탄다.

## 8. 테스트

- **단위 테스트**: `ActivationPolicyManager`의 정책 결정 로직을 순수 함수로 분리 — 등록된 창 수 → `.regular`(≥1) / `.accessory`(0) 매핑. 등록/해제 시퀀스 검증.
- **수동 테스트**: `docs/manual-test-checklist.md`에 "12. 홈 창" 섹션 추가 — ①실행 시 홈 창+독 표시 ②캡처 버튼 3종 동작 ③홈 창 닫으면 독 사라짐+메뉴바 유지 ④편집기 여러 개일 때 독 유지, 다 닫으면 사라짐 ⑤메뉴 "홈…"으로 재열기 ⑥모든 창 닫아도 앱 상주

## 9. 버전

v0.4.0 — AppInfo.version / Info.plist CFBundleShortVersionString "0.4.0", CFBundleVersion 5
