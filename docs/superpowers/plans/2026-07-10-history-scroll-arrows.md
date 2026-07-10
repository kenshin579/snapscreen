# 최근 캡처 슬라이드 좌우 화살표 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 최근 캡처 가로 슬라이드에 좌우 스크롤 화살표를 얹어, 더 볼 캡처가 있으면 `‹`/`›`를 띄우고 클릭으로 넘겨보게 한다.

**Architecture:** `HomeView`의 최근 캡처 `ScrollView`를 `ScrollViewReader`로 감싸고, `PreferenceKey`로 가로 오프셋을, `GeometryReader`로 뷰포트 너비를 추적한다. 오프셋/콘텐츠/뷰포트 비교로 양 끝 화살표 표시 여부를 정하고, 클릭 시 `scrollTo`로 한 뷰포트 이동. 모델·클릭·삭제는 그대로.

**Tech Stack:** SwiftUI(ScrollViewReader, PreferenceKey, GeometryReader).

---

## 파일 구조

| 파일 | 책임 | 상태 |
|---|---|---|
| `Home/HomeView.swift` | 최근 캡처 스크롤에 오프셋 추적 + 좌우 화살표 오버레이 + 클릭 스크롤 | 수정 |
| `docs/manual-test-checklist.md`, `README.md`, `Support/AppInfo.swift`, `Resources/Info.plist` | 문서·버전 | 수정 |

SwiftUI 레이아웃/스크롤이라 자동 테스트는 없다(로직·모델 무변경). 검증은 clean 빌드 경고 0 + 기존 78 테스트 회귀 없음 + 수동.

---

### Task 1: HomeView 좌우 화살표

**Files:**
- Modify: `Sources/SnapScreenKit/Home/HomeView.swift`

- [ ] **Step 1: 상태 + 상수 프로퍼티 추가**

`HomeView`의 `items` 배열 다음에 추가:

```swift
    @State private var scrollOffset: CGFloat = 0
    @State private var viewportWidth: CGFloat = 0
    private let itemStride: CGFloat = 130 // 썸네일 120 + 간격 10

    private var contentWidth: CGFloat {
        max(0, CGFloat(history.entries.count) * itemStride - 10)
    }
    private var canScrollLeft: Bool { scrollOffset > 2 }
    private var canScrollRight: Bool { scrollOffset < contentWidth - viewportWidth - 2 }
```

- [ ] **Step 2: 최근 캡처 else 블록을 화살표 스크롤러로 교체**

body의 아래 블록(현재):

```swift
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 10) {
                        ForEach(history.entries) { entry in
                            thumbnail(entry)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(height: 86)
            }
```

를 아래로 교체:

```swift
            } else {
                capturesScroller
            }
```

- [ ] **Step 3: capturesScroller + 화살표 + 스크롤 헬퍼 추가**

`thumbnail(_:)` 메서드 **앞**에 아래를 추가:

```swift
    @ViewBuilder
    private var capturesScroller: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(history.entries) { entry in
                        thumbnail(entry)
                    }
                }
                .padding(.vertical, 2)
                .background(GeometryReader { geo in
                    Color.clear.preference(key: ScrollOffsetKey.self,
                                           value: -geo.frame(in: .named("hscroll")).minX)
                })
            }
            .coordinateSpace(name: "hscroll")
            .onPreferenceChange(ScrollOffsetKey.self) { scrollOffset = $0 }
            .background(GeometryReader { geo in
                Color.clear
                    .onAppear { viewportWidth = geo.size.width }
                    .onChange(of: geo.size.width) { viewportWidth = geo.size.width }
            })
            .overlay(alignment: .leading) {
                if canScrollLeft { arrow("chevron.left") { scrollBy(-1, proxy: proxy) } }
            }
            .overlay(alignment: .trailing) {
                if canScrollRight { arrow("chevron.right") { scrollBy(1, proxy: proxy) } }
            }
        }
        .frame(height: 86)
    }

    private func arrow(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.black.opacity(0.55)))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
    }

    /// direction: -1 왼쪽 / +1 오른쪽. 한 뷰포트만큼 근접 항목으로 스크롤한다.
    private func scrollBy(_ direction: Int, proxy: ScrollViewProxy) {
        guard !history.entries.isEmpty else { return }
        let perPage = max(1, Int(viewportWidth / itemStride))
        let currentLeading = Int((scrollOffset / itemStride).rounded())
        let target = min(max(currentLeading + direction * perPage, 0), history.entries.count - 1)
        withAnimation { proxy.scrollTo(history.entries[target].id, anchor: .leading) }
    }
```

- [ ] **Step 4: ScrollOffsetKey PreferenceKey 추가**

파일 맨 끝(`}` 뒤, 파일 최하단)에 추가:

```swift

private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
```

- [ ] **Step 5: 빌드 + 로컬 실행 확인**

Run: `rm -rf .build && swift build 2>&1 | grep -ci warning` → 0
(주의: `.onChange(of:)` 시그니처가 macOS 14 SwiftUI에서 경고를 낼 수 있다. 계획의 `.onChange(of: geo.size.width) { viewportWidth = geo.size.width }`는 값 무시 zero-parameter 형식이다. 만약 deprecated 경고가 나면 `.onChange(of: geo.size.width) { _, newWidth in viewportWidth = newWidth }` 형식으로 바꿔 경고 0으로 맞춘다.)
Run: `swift test 2>&1 | grep -E "Executed [0-9]+ tests" | tail -1` → 78 유지
Run: `Scripts/run.sh` → 캡처를 여러 개 만들어 홈 창에서 좌우 화살표가 스크롤 가능할 때만 뜨는지, 클릭 시 넘어가는지, 끝에서 사라지는지 확인(수동)

- [ ] **Step 6: 커밋**

```bash
git add Sources/SnapScreenKit/Home/HomeView.swift
git commit -m "$(cat <<'EOF'
feat: 최근 캡처 슬라이드 좌우 스크롤 화살표

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: 문서 + v0.10.2 범프 + PR

**Files:**
- Modify: `docs/manual-test-checklist.md`, `README.md`
- Modify: `Sources/SnapScreenKit/Support/AppInfo.swift`, `Resources/Info.plist`

- [ ] **Step 1: 체크리스트 §19 보강**

`docs/manual-test-checklist.md`의 "## 19. 최근 캡처 (히스토리)" 목록 끝에 추가:

```markdown
- [ ] 캡처가 많아 스크롤될 때 좌우에 화살표가 나타나고, 끝에 닿으면 해당 화살표가 사라지며, 클릭하면 그 방향으로 넘어간다
```

- [ ] **Step 2: 버전 범프**

- `Sources/SnapScreenKit/Support/AppInfo.swift`: `version = "0.10.2"`
- Info.plist:
```bash
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString 0.10.2" Resources/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion 18" Resources/Info.plist
```

- [ ] **Step 3: README 갱신**

`README.md`를 Read 후, 최근 캡처 갤러리 설명에 "좌우 화살표로 넘겨보기" 취지를 자연스럽게 반영(짧게). 과한 변경 금지.

- [ ] **Step 4: 최종 검증**

```bash
swift test 2>&1 | grep -E "Executed [0-9]+ tests" | tail -1        # 78 PASS
rm -rf .build && swift build 2>&1 | grep -ci warning               # 0
Scripts/bundle.sh release                                          # OK
file -I README.md docs/manual-test-checklist.md                    # utf-8
/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist  # 0.10.2
/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" Resources/Info.plist              # 18
```

- [ ] **Step 5: Commit + Push + PR**

```bash
git add docs/ README.md Sources/ Resources/
git commit -m "$(cat <<'EOF'
chore: 슬라이드 화살표 문서 + v0.10.2 버전 범프

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
git push -u origin feat/history-scroll-arrows
gh pr create --title "feat: 최근 캡처 슬라이드 좌우 화살표" --body "$(cat <<'EOF'
## Summary
- 최근 캡처 가로 슬라이드에 좌우 스크롤 화살표 추가 — 더 볼 캡처가 있을 때만 `‹`/`›` 표시, 클릭 시 그 방향으로 한 뷰포트 스크롤
- 스크롤 오프셋(PreferenceKey) + 뷰포트 너비(GeometryReader)로 표시 조건 판정, 끝에 닿으면 해당 화살표 숨김
- v0.10.2 범프

## 설계/계획
- Spec: `docs/superpowers/specs/2026-07-10-history-scroll-arrows-design.md`
- Plan: `docs/superpowers/plans/2026-07-10-history-scroll-arrows.md`

## Test plan
- [x] clean 빌드 경고 0, 기존 78 테스트 통과
- [ ] 수동: 스크롤 가능 시 화살표 표시·끝에서 숨김·클릭 이동 (checklist §19)
EOF
)"
```
`--reviewer` 플래그 쓰지 말 것.

## 실행 순서와 검증 한계

- Task 1(화살표 UI) → 2(문서·범프·PR).
- SwiftUI 스크롤/오버레이라 자동 테스트 불가 → 수동 §19. 기존 78 테스트는 회귀 없음만 확인.
- 릴리스(`make release VERSION=v0.10.2`)는 PR 머지 후 별도.
