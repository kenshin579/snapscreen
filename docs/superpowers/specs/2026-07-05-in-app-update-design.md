# 인앱 업데이트 설계 문서

- 날짜: 2026-07-05
- 상태: 승인됨 (브레인스토밍 완료)
- 대상 릴리스: v0.2.0

## 1. 개요

설정 창에 현재 버전을 표시하고, GitHub Releases의 최신 버전을 확인해 "업그레이드" 클릭 한 번으로 새 버전을 설치한다.

**요구사항**
- 설정 창에 현재 버전 표시
- 앱 시작 시 자동 업데이트 확인 + 설정 창에서 수동 확인
- 새 버전 발견 시 메뉴바 메뉴 최상단에 "업데이트 가능 (vX.Y.Z)…" 항목 표시 (클릭 = 설정 창 열기)
- 설정 창에서 업그레이드 클릭 → 다운로드 → 설치 → 재실행

**비목표**
- Sparkle 도입 (Developer ID 서명 도입 시 재검토)
- 주기적(24시간) 재확인 — 시작 시 1회 + 수동 확인으로 충분 (v0.3 후보)
- 다운로드 진행률 표시 (zip ~300KB)
- 델타 업데이트, 자동(무확인) 설치

## 2. 접근법 결정

**자체 GitHub Releases 업데이터** (Sparkle 대비):
- 기존 릴리스 인프라(GitHub Releases + zip) 그대로 사용, 서명 키/appcast 관리 없음
- 앱이 직접 다운로드한 파일에는 quarantine 속성이 붙지 않아 업데이트 시 `xattr -cr` 불필요 (최초 설치 시에만 필요)
- 미서명(ad-hoc) 앱에서는 Sparkle의 핵심 가치(서명 검증) 대비 인프라 비용이 큼

**알려진 제약 (업데이트 방식 무관)**: ad-hoc 서명은 버전마다 코드 해시가 달라져 업데이트 후 화면 기록 권한을 다시 켜야 할 수 있다. 재실행 후 안내 문구로 대응하며, 근본 해결은 Developer ID 서명뿐이다.

## 3. 구성 요소

새 모듈 `Sources/SnapScreenKit/Updater/` 3개 파일:

| 파일 | 책임 | AppKit 의존 |
|---|---|---|
| `UpdateChecker.swift` | GitHub API 조회, 시맨틱 버전 비교, zip 에셋 선택 | 비의존 (단위 테스트 대상) |
| `UpdateInstaller.swift` | zip 다운로드 → 압축 해제 → 검증 → 번들 교체 → 재실행 | 의존 |
| `UpdateState.swift` | `@MainActor ObservableObject` — 설정 창/메뉴바 공유 상태 | 의존 (ObservableObject) |

**UpdateChecker**
- `GET https://api.github.com/repos/kenshin579/snapscreen/releases/latest` (비인증, 시간당 60회 제한 — 시작 시 1회 + 수동이라 충분)
- 응답에서 `tag_name`("v0.2.0")과 이름이 `.zip`으로 끝나는 에셋의 `browser_download_url` 추출
- 시맨틱 버전 비교는 순수 함수 `compare(_:_:)`로 분리 (자릿수 다른 경우 포함)
- 결과: `UpdateStatus` — `.upToDate` / `.available(version: String, downloadURL: URL)` / `.failed(Error)`
- 현재 버전 진실 공급원: `AppInfo.version` (릴리스 스크립트가 태그↔AppInfo↔Info.plist 일치를 이미 강제)

## 4. 데이터 흐름

```
앱 시작 (AppDelegate)
  → UpdateChecker.check() (백그라운드, 실패 시 조용히 무시)
  → UpdateState.status 갱신
     ├→ .available: StatusItemController가 메뉴 최상단에
     │   "업데이트 가능 (vX.Y.Z)…" + 구분선 추가 → 클릭 시 설정 창 열기
     └→ 설정 창 "정보" 섹션에 반영

설정 창 [업데이트 확인] → 동일 check() 수동 호출
설정 창 [업그레이드] → UpdateInstaller.install()
```

## 5. 설정 UI + 메뉴바

**설정 창 — 기존 Form 맨 아래 "정보" 섹션 추가:**

- "버전: 0.1.0" (AppInfo.version)
- 상태 줄: 확인 중… / 최신 버전입니다 ✓ / vX.Y.Z 사용 가능 / 확인 실패 (네트워크 확인)
- [업데이트 확인] 버튼 (확인 중·설치 중 비활성)
- [업그레이드] 버튼 — `.available`일 때만 표시, 설치 중에는 "다운로드 중…"으로 비활성

**메뉴바:** `.available`일 때만 메뉴 최상단에 "업데이트 가능 (vX.Y.Z)…" 항목 + 구분선. `.upToDate`면 항목 없음(기존 메뉴 그대로). `UpdateState` 변화를 구독해 메뉴 갱신.

## 6. 설치 플로우 (UpdateInstaller)

1. zip 다운로드 — URLSession → 임시 디렉토리
2. 압축 해제 — `ditto -x -k` (릴리스 zip 생성 도구와 동일)
3. 검증 — 새 `SnapScreen.app` 존재 + `Info.plist`의 `CFBundleShortVersionString`이 기대 버전과 일치
4. 번들 교체 — 현재 위치는 `Bundle.main.bundleURL` 기준:
   - 실행 중인 번들 → 임시 위치로 이동 (macOS는 실행 중 rename 허용)
   - 새 번들을 원래 위치로 이동
5. 재실행 — 분리된 프로세스로 `sleep 1; open <경로>` 실행 후 `NSApp.terminate`
6. 업데이트 후 첫 실행 안내 — UserDefaults에 마지막 실행 버전 기록, 버전이 바뀐 첫 실행에 1회 "업데이트 완료. 화면 기록 권한을 다시 켜야 할 수 있습니다" 알림

## 7. 에러 처리

| 상황 | 처리 |
|---|---|
| 릴리스 조회 실패 (자동 확인) | 조용히 무시 (best-effort) |
| 릴리스 조회 실패 (수동 확인) | 설정 창에 "확인 실패" 표시 |
| 다운로드/압축 해제/검증 실패 | 알림창 + "릴리스 페이지 열기" 폴백 버튼 |
| 번들 교체 권한 없음 | 동일 폴백 |
| 교체 후 재실행 실패 | 앱은 이미 교체됨 — 수동 실행 안내 알림 |

## 8. 테스트

- **단위 테스트**: 시맨틱 버전 비교(같음/크다/작다/자릿수 상이), GitHub 릴리스 JSON 파싱(픽스처 문자열), zip 에셋 선택 로직
- **수동 테스트**: 업그레이드 E2E는 구버전 설치 → 이 기능이 담긴 신버전 릴리스 후에만 검증 가능. `docs/manual-test-checklist.md`에 "11. 업데이트" 섹션 추가 (버전 표시, 수동 확인, 메뉴바 항목, 업그레이드 설치→재실행, 실패 폴백)
- **릴리스 전제**: zip 에셋 이름 `SnapScreen-vX.Y.Z.zip` (현재 release.yml이 이미 이 형식) — 이름 규약을 바꾸면 구버전 업데이터가 에셋을 못 찾으므로 유지할 것
