# 최근 캡처 호버 삭제 버튼 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 최근 캡처 썸네일에 호버 시 우상단 X 버튼을 띄워 클릭 즉시 삭제하고, 우클릭 메뉴는 제거한다.

**Architecture:** `HomeView.thumbnail(_:)`을 `ZStack(topTrailing)`으로 재구성 — 이미지 열기 Button 위에 호버 시에만 X Button을 얹는다. `@State hoveredID`로 항목별 호버를 추적. 모델·저장·클릭 재편집은 그대로.

**Tech Stack:** SwiftUI(onHover, ZStack overlay).

---

## 파일 구조

| 파일 | 책임 | 상태 |
|---|---|---|
| `Home/HomeView.swift` | 썸네일 호버 X 버튼 + 우클릭 메뉴 제거 | 수정 |
| `docs/manual-test-checklist.md`, `Support/AppInfo.swift`, `Resources/Info.plist` | 문서·버전 | 수정 |

SwiftUI 호버/레이아웃이라 자동 테스트 없음(모델 무변경). 검증은 clean 빌드 경고 0 + 기존 78 테스트 회귀 없음 + 수동.

---

### Task 1: 호버 X 삭제 버튼

**Files:**
- Modify: `Sources/SnapScreenKit/Home/HomeView.swift`

- [ ] **Step 1: hoveredID 상태 추가**

`@State private var leadingID: UUID?`(현재 30행) 다음 줄에 추가:

```swift
    @State private var hoveredID: UUID?
```

- [ ] **Step 2: thumbnail(_:)을 ZStack + 호버 X로 재구성**

현재 `thumbnail(_:)`(현재 140~161행):

```swift
    @ViewBuilder
    private func thumbnail(_ entry: HistoryEntry) -> some View {
        let image = NSImage(contentsOf: history.thumbnailURL(id: entry.id))
        Button { onOpenEntry(entry) } label: {
            Group {
                if let image {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "photo").foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(width: 120, height: 78)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .help(entry.date.formatted(date: .abbreviated, time: .shortened))
        .contextMenu {
            Button("삭제", role: .destructive) { history.remove(id: entry.id) }
        }
    }
```

를 아래로 교체:

```swift
    @ViewBuilder
    private func thumbnail(_ entry: HistoryEntry) -> some View {
        let image = NSImage(contentsOf: history.thumbnailURL(id: entry.id))
        ZStack(alignment: .topTrailing) {
            Button { onOpenEntry(entry) } label: {
                Group {
                    if let image {
                        Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Image(systemName: "photo").foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(width: 120, height: 78)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.12)))
            }
            .buttonStyle(.plain)

            if hoveredID == entry.id {
                Button { history.remove(id: entry.id) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(Color.black.opacity(0.6)))
                }
                .buttonStyle(.plain)
                .padding(4)
                .help("삭제")
            }
        }
        .help(entry.date.formatted(date: .abbreviated, time: .shortened))
        .onHover { hovering in
            if hovering { hoveredID = entry.id }
            else if hoveredID == entry.id { hoveredID = nil }
        }
    }
```

- [ ] **Step 3: 빌드 + 로컬 실행 확인**

Run: `rm -rf .build && swift build 2>&1 | grep -ci warning` → 0
Run: `swift test 2>&1 | grep -E "Executed [0-9]+ tests" | tail -1` → 78 유지
Run: `Scripts/run.sh` → 홈 창에서 썸네일에 마우스 올리면 우상단 X 표시, 클릭 시 삭제, 썸네일 본체 클릭은 편집기 열기, 우클릭 메뉴 없음 확인(수동)

- [ ] **Step 4: 커밋**

```bash
git add Sources/SnapScreenKit/Home/HomeView.swift
git commit -m "$(cat <<'EOF'
feat: 최근 캡처 호버 시 X 버튼으로 삭제 (우클릭 메뉴 대체)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: 문서 + v0.10.4 범프 + PR

**Files:**
- Modify: `docs/manual-test-checklist.md`
- Modify: `Sources/SnapScreenKit/Support/AppInfo.swift`, `Resources/Info.plist`

- [ ] **Step 1: 체크리스트 §19 보강**

`docs/manual-test-checklist.md`의 "## 19. 최근 캡처 (히스토리)" 목록 끝에 추가:

```markdown
- [ ] 썸네일에 마우스를 올리면 우상단에 X가 나타나고, 클릭하면 즉시 삭제된다(썸네일 본체 클릭은 편집기 열기)
```

- [ ] **Step 2: 버전 범프**

- `Sources/SnapScreenKit/Support/AppInfo.swift`: `version = "0.10.4"`
- Info.plist:
```bash
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString 0.10.4" Resources/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion 20" Resources/Info.plist
```

- [ ] **Step 3: 최종 검증**

```bash
swift test 2>&1 | grep -E "Executed [0-9]+ tests" | tail -1        # 78 PASS
rm -rf .build && swift build 2>&1 | grep -ci warning               # 0
Scripts/bundle.sh release                                          # OK
file -I docs/manual-test-checklist.md                              # utf-8
/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist  # 0.10.4
/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" Resources/Info.plist              # 20
```

- [ ] **Step 4: Commit + Push + PR**

```bash
git add docs/ Sources/ Resources/
git commit -m "$(cat <<'EOF'
chore: 호버 삭제 문서 + v0.10.4 버전 범프

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
git push -u origin feat/history-hover-delete
gh pr create --title "feat: 최근 캡처 호버 삭제 버튼" --body "$(cat <<'EOF'
## Summary
- 최근 캡처 썸네일에 호버 시 우상단 X 버튼 표시 → 클릭 즉시 삭제
- 기존 우클릭 컨텍스트 메뉴 삭제를 X 버튼으로 일원화(발견성↑)
- `ZStack(topTrailing)` + `@State hoveredID` + `.onHover`, 썸네일 본체 클릭(편집기 열기)과 분리
- v0.10.4 범프

## 설계/계획
- Spec: `docs/superpowers/specs/2026-07-10-history-hover-delete-design.md`
- Plan: `docs/superpowers/plans/2026-07-10-history-hover-delete.md`

## Test plan
- [x] clean 빌드 경고 0, 기존 78 테스트 통과
- [ ] 수동: 호버 X 표시·클릭 삭제·본체 클릭 편집기·우클릭 메뉴 없음 (checklist §19)
EOF
)"
```
`--reviewer` 플래그 쓰지 말 것.

## 실행 순서와 검증 한계

- Task 1(호버 X UI) → 2(문서·범프·PR).
- SwiftUI 호버라 자동 테스트 불가 → 수동 §19. 기존 78 테스트는 회귀 없음만 확인.
- 릴리스(`make release VERSION=v0.10.4`)는 PR 머지 후 별도.
