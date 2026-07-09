# 최근 캡처 갤러리/히스토리 설계 문서

- 날짜: 2026-07-09
- 상태: 승인됨 (브레인스토밍 완료)
- 대상 릴리스: v0.10.0

## 1. 배경

홈 창 설계(v0.4.0) 때 "갤러리형 홈은 히스토리 저장 기능이 선행되어야 한다"며 미뤄뒀던 기능. 캡처를 자동으로 보관해 두면 **저장하지 않고 닫아버린 캡처도 되살릴 수 있다** — CleanShot·Shottr가 제공하는 핵심 편의. 홈 창을 런처에서 대시보드로 진화시킨다.

## 2. 범위

- **모든 캡처를 자동 기록** — 캡처 직후(편집기가 열리는 순간) **원본**을 히스토리에 저장. 편집(주석) 결과는 반영하지 않음(그건 ⌘S 저장의 몫)
- 보관 정책: **최근 50개** — 초과 시 가장 오래된 항목부터 자동 삭제
- **홈 창에 갤러리 통합** — 캡처 버튼 아래 최근 캡처 썸네일 그리드(스크롤)
- **클릭 → 편집기로 다시 열기** (주석·자르기·저장·복사 모두 가능, scale 보존)
- **우클릭 → 삭제** 컨텍스트 메뉴
- 앱 재시작 후에도 히스토리 유지(디스크 영속화)

**비목표**: 편집 결과를 히스토리에 반영, 호버 빠른 복사 버튼, 전체 비우기, 보관 개수 설정 UI, iCloud 동기화, 검색/필터, 별도 히스토리 창.

## 3. 구성 요소

| 파일 | 책임 | AppKit |
|---|---|---|
| `History/HistoryStore.swift` (신규) | 영속화 계층 — 디스크 저장/로드/상한 롤링/삭제, `ObservableObject`로 entries 노출 | CoreGraphics/Foundation (테스트 대상) |
| `History/HistoryEntry.swift` (신규) | 항목 메타 모델(`id`, 파일명, 날짜, `scale`), `Codable` | 비의존 |
| `AppCore/CaptureCoordinator.swift` (수정) | `handleCaptured`에서 히스토리 기록 | — |
| `AppCore/AppDelegate.swift` (수정) | `HistoryStore` 생성·주입 | — |
| `Home/HomeView.swift` (수정) | 최근 캡처 그리드 섹션 + 클릭/우클릭 | 의존 |
| `Home/HomeWindowController.swift` (수정) | 창 크기 확대, store/콜백 주입 | 의존 |

## 4. 영속화 (`HistoryStore`)

- **위치**: `~/Library/Application Support/SnapScreen/History/` (`FileManager.urls(for: .applicationSupportDirectory)` + 번들 ID 하위). 테스트를 위해 **디렉터리 URL 주입 가능**(`init(directory: URL)`)
- **파일 구조**:
  - `<id>.png` — 원본 (기존 `PNGEncoder.encode(image, scale:)` 재사용, DPI 메타 포함)
  - `<id>.thumb.png` — 썸네일(가로 최대 320px 다운스케일) — 갤러리 로딩 성능용
  - `index.json` — `[HistoryEntry]` (최신순 아님, 저장 시 정렬은 로드 쪽에서)
- **모델**:
```swift
public struct HistoryEntry: Codable, Equatable, Identifiable {
    public let id: UUID
    public let date: Date
    public let scale: CGFloat   // 재편집 시 Retina 배율 복원에 필수
}
```
  (파일명은 `id.uuidString` 기반으로 유도 — 별도 필드 불필요)
- **API** (`@MainActor` 클래스, 인코딩/IO는 내부에서 백그라운드 처리 후 메인으로 결과 반영):
```swift
@MainActor
public final class HistoryStore: ObservableObject {
    @Published public private(set) var entries: [HistoryEntry]  // 최신순
    public init(directory: URL, limit: Int = 50)
    public func add(image: CGImage, scale: CGFloat)   // 비동기 인코딩·저장 → 완료 시 entries 갱신 + 상한 롤링
    public func loadImage(id: UUID) -> CGImage?        // 원본 로드 (재편집용)
    public func thumbnailURL(id: UUID) -> URL          // 갤러리 표시용
    public func remove(id: UUID)                       // 파일 + 메타 삭제
}
```
- **상한 롤링**: `add` 완료 후 `entries.count > limit`이면 초과분(가장 오래된 것)의 png/thumb 파일 삭제 + index 갱신
- **불변식**: index.json이 진실의 원천. 로드 시 index에 있는데 파일이 없는 항목은 제거(자가 치유), index 파싱 실패 시 빈 히스토리로 초기화(파일 잔존은 무해)

## 5. 기록 지점 (`CaptureCoordinator`)

`handleCaptured(result)`에서 편집기 열기와 **병행**으로 `historyStore.add(image: result.image, scale: result.scale)` 호출. PNG 인코딩·디스크 쓰기는 store 내부의 백그라운드 큐에서 수행 → 캡처→편집기 흐름을 막지 않는다. `HistoryStore`는 `AppDelegate`가 생성해 코디네이터·홈 창에 주입(기존 `updateState`/`settings` 주입 패턴).

## 6. 갤러리 UI (홈 창)

- `HomeView`에 "최근 캡처" 섹션 추가: 캡처 버튼 3개 아래, `LazyVGrid`(3열 내외) + `ScrollView`
- 각 셀: 썸네일(`AsyncImage` 대신 파일 URL에서 `NSImage` 로드 — 로컬이라 동기 로드 무해, 셀 크기 고정) + 날짜 툴팁(`.help`)
- 히스토리 비면 "아직 캡처가 없습니다" 플레이스홀더
- `HistoryStore`가 `ObservableObject`라 새 캡처가 오면 자동 갱신
- 홈 창 크기: 기존 고정 크기에서 세로 확대(그리드 영역 포함, 고정 크기 유지 + 그리드만 스크롤)
- **클릭**: `onOpenEntry(HistoryEntry)` 클로저 → `AppDelegate`(또는 코디네이터)가 `loadImage(id:)`로 원본 로드 + `CaptureResult(image:scale:)` 구성 → 기존 `handleCaptured` 경로로 편집기 열기 (히스토리 재기록 방지 위해 편집기 열기만 하는 별도 진입점 사용)
- **우클릭**: `.contextMenu { Button("삭제") { store.remove(id:) } }`

## 7. 에러 처리 / 엣지

- 디렉터리 생성/쓰기 실패: 히스토리 기록만 조용히 스킵(캡처·편집 흐름은 정상). 히스토리는 부가 기능 — 하드 실패로 만들지 않는다
- 클릭 시 원본 로드 실패(파일 삭제됨 등): `Notifier.show`로 안내 + 해당 항목 index에서 제거
- index.json 손상: 빈 히스토리로 초기화
- 같은 순간 다중 캡처: id가 UUID라 충돌 없음

## 8. 테스트

- **단위** (`HistoryStoreTests`, 임시 디렉터리 주입):
  - add 후 entries 최신순 + 파일 존재(png/thumb)
  - limit 초과 시 오래된 항목 롤링(파일도 삭제)
  - remove 후 entries·파일 제거
  - scale 왕복(저장 → 다시 로드한 entry의 scale 일치)
  - index에 있으나 파일 없는 항목 자가 치유, 손상 index 초기화
  - (add가 비동기면 XCTestExpectation으로 대기)
- **수동**: 체크리스트 "19. 최근 캡처" — 캡처 직후 홈 갤러리에 등장, 클릭 재편집(배율 정상), 우클릭 삭제, 저장 안 한 캡처도 남는지, 앱 재시작 후 유지, 51번째 캡처 시 가장 오래된 항목 소멸

## 9. 버전

v0.10.0 — `AppInfo.version` "0.10.0", `Info.plist` `CFBundleShortVersionString` "0.10.0", `CFBundleVersion` 16.
