# 히스토리 관리(전체 비우기 + 보관 개수) 설계 문서

- 날짜: 2026-07-11
- 상태: 승인됨 (브레인스토밍 완료)
- 대상 릴리스: v0.11.0

## 1. 배경

최근 캡처 히스토리(v0.10.x)는 개별 삭제만 가능하고 보관 개수가 50개로 고정이다. 사용자가 히스토리를 **한 번에 비우거나** 보관 **개수를 조절**할 수 있게 확장한다.

## 2. 범위

- **전체 비우기**: 홈 창 "최근 캡처" 헤더 우측 "모두 지우기" 버튼(항목이 있을 때만) → 확인 다이얼로그 → 전체 삭제
- **보관 개수 설정**: 설정 창 "히스토리" 섹션의 Picker(20 / 50 / 100 / 200, 기본 50). 변경 시 즉시 반영(줄이면 초과분 트림)

**비목표**: 무제한 옵션, 자유 입력 개수, 검색/필터, 기간 기반 정리.

## 3. 구성 요소

| 파일 | 책임 | 상태 |
|---|---|---|
| `History/HistoryStore.swift` | `limit`를 가변으로, `clear()`/`updateLimit(_:)` 추가 | 수정 |
| `Settings/SettingsStore.swift` | `historyLimit: Int`(기본 50, UserDefaults) | 수정 |
| `Settings/SettingsView.swift` | "히스토리" 섹션 + 보관 개수 Picker | 수정 |
| `AppCore/AppDelegate.swift` | `HistoryStore`에 초기 limit 주입 + `historyLimit` 구독→`updateLimit` | 수정 |
| `Home/HomeView.swift` | "모두 지우기" 버튼 + 확인 다이얼로그 | 수정 |
| `Tests/SnapScreenKitTests/HistoryStoreTests.swift` | `clear`/`updateLimit` 테스트 | 수정 |

## 4. HistoryStore 확장

- `private let limit: Int` → `private var limit: Int`
- 추가:
```swift
    /// 히스토리 전체 삭제 (파일 + 메타)
    public func clear() {
        for entry in entries { archive.delete(id: entry.id) }
        entries = []
        archive.writeIndex(entries)
    }

    /// 보관 개수 변경. 줄이면 초과분(오래된 것부터)을 즉시 삭제한다.
    public func updateLimit(_ newLimit: Int) {
        limit = newLimit
        while entries.count > limit {
            let removed = entries.removeLast()
            archive.delete(id: removed.id)
        }
        archive.writeIndex(entries)
    }
```
- `entries`는 최신순이므로 `removeLast()`가 가장 오래된 항목. 기존 `insert`의 롤링 로직과 동일 규칙

## 5. 보관 개수 설정 (SettingsStore / SettingsView)

`SettingsStore`:
```swift
    // Key에 추가
    static let historyLimit = "historyLimit"

    @Published public var historyLimit: Int = 50 {
        didSet { defaults.set(historyLimit, forKey: Key.historyLimit) }
    }

    // load()에 추가 (0/미설정 방지)
    let storedLimit = defaults.integer(forKey: Key.historyLimit)
    historyLimit = storedLimit == 0 ? 50 : storedLimit
```

`SettingsView`의 Form에 섹션 추가(저장 섹션 근처):
```swift
    Section("히스토리") {
        Picker("보관 개수", selection: $settings.historyLimit) {
            ForEach([20, 50, 100, 200], id: \.self) { Text("\($0)개").tag($0) }
        }
    }
```

## 6. 설정 ↔ 스토어 연동 (AppDelegate)

- `HistoryStore` 생성 시 `limit: coordinator.settings.historyLimit`(또는 별도 settings 참조) 주입 — 초기 개수 반영
- `settings.$historyLimit`를 Combine으로 구독해 변경 시 `historyStore.updateLimit($0)` 호출. `AppDelegate`가 store와 settings를 모두 참조하므로 여기서 연결(기존 `updateState`/sink 소유 패턴). 구독 토큰은 `AppDelegate`가 보유
- `SettingsStore.load()`가 `AppDelegate` 시작 시 호출되어 저장값이 반영된 뒤 `HistoryStore`가 생성되도록 순서 유지(coordinator.init에서 settings.load() 수행 확인)

## 7. 전체 비우기 UI (HomeView)

- "최근 캡처" 헤더 `HStack`의 `Spacer()` 다음에 조건부 버튼:
```swift
    if !history.entries.isEmpty {
        Button("모두 지우기") { showClearConfirm = true }
            .font(.system(size: 11))
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
    }
```
- `@State private var showClearConfirm = false` + 확인 다이얼로그:
```swift
    .confirmationDialog("최근 캡처를 모두 지울까요?", isPresented: $showClearConfirm, titleVisibility: .visible) {
        Button("모두 지우기", role: .destructive) { history.clear() }
        Button("취소", role: .cancel) {}
    }
```

## 8. 에러 처리 / 엣지

- `clear()`/`updateLimit`의 파일 삭제는 `archive.delete`(내부 `try?`)라 실패해도 조용. index는 항상 메모리 상태로 재기록
- 개수를 **늘리면** 트림 없음(기존 항목 유지). **줄이면** 즉시 트림
- 비우는 중 새 캡처가 오면 UUID라 충돌 없음(정상 add 경로)
- 히스토리 0개면 "모두 지우기" 버튼 미표시

## 9. 테스트

- **단위**(`HistoryStoreTests` 추가, 임시 디렉터리):
  - `clear()`: 여러 항목 add 후 clear → entries 빔 + 파일 삭제 + 재로드해도 빔
  - `updateLimit(작게)`: limit=3에서 5개 add 후 `updateLimit(2)` → 2개만 남고 오래된 3개 파일 삭제, 재로드 유지
  - `updateLimit(크게)`: 늘려도 기존 유지
- **수동**: 체크리스트 §19에 "헤더 '모두 지우기' 확인 후 비워짐", "설정 히스토리 보관 개수 변경 시 즉시 반영(줄이면 오래된 것부터 사라짐)"

## 10. 버전

v0.11.0 — `AppInfo.version` "0.11.0", `Info.plist` `CFBundleShortVersionString` "0.11.0", `CFBundleVersion` 21.
