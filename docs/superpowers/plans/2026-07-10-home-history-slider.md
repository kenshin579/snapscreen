# 홈 창 최근 캡처 가로 슬라이드 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 홈 창 최근 캡처를 고정 높이 세로 그리드에서 가로 한 줄 슬라이드로 바꿔 세로 빈 공간을 없앤다.

**Architecture:** `HomeView`의 "최근 캡처" 블록만 `ScrollView(.horizontal)` + `LazyHStack`으로 교체하고 썸네일을 고정 크기(120×78)로 만든다. 모델·저장·클릭·삭제 로직은 그대로.

**Tech Stack:** SwiftUI.

---

## 파일 구조

| 파일 | 책임 | 상태 |
|---|---|---|
| `Home/HomeView.swift` | 최근 캡처 섹션 가로 스크롤화 + 썸네일 고정폭 | 수정 |
| `docs/manual-test-checklist.md`, `README.md`, `Support/AppInfo.swift`, `Resources/Info.plist` | 문서·버전 | 수정 |

레이아웃만 변경이라 자동 테스트는 없다(기존 78개 회귀 없음 확인). 검증은 clean 빌드 경고 0 + 수동.

---

### Task 1: HomeView 가로 슬라이드

**Files:**
- Modify: `Sources/SnapScreenKit/Home/HomeView.swift`

- [ ] **Step 1: columns 상수 제거**

`HomeView`의 아래 줄을 삭제한다(가로 스크롤에선 불필요):

```swift
    private let columns = [GridItem(.adaptive(minimum: 116), spacing: 10)]
```

- [ ] **Step 2: "최근 캡처" 블록을 가로 스크롤로 교체**

body에서 아래 블록(현재 61~75행):

```swift
            if history.entries.isEmpty {
                Text("아직 캡처가 없습니다")
                    .font(.system(size: 12)).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(history.entries) { entry in
                            thumbnail(entry)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(height: 260)
            }
```

를 아래로 교체:

```swift
            if history.entries.isEmpty {
                Text("아직 캡처가 없습니다")
                    .font(.system(size: 12)).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, height: 78)
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

- [ ] **Step 3: thumbnail을 고정 폭으로**

`thumbnail(_:)`에서 프레임 지정 두 줄을 교체한다. 현재(100~101행):

```swift
            .frame(height: 78)
            .frame(maxWidth: .infinity)
```

를 아래로 교체(가로 스크롤에선 고정 폭이어야 나란히 배치됨):

```swift
            .frame(width: 120, height: 78)
```

- [ ] **Step 4: 빌드 + 로컬 실행 확인**

Run: `rm -rf .build && swift build 2>&1 | grep -ci warning` → 0
Run: `swift test 2>&1 | grep -E "Executed [0-9]+ tests" | tail -1` → 78 유지
Run: `Scripts/run.sh` → 홈 창의 최근 캡처가 가로 한 줄로 표시되고 창 세로에 큰 빈 공간이 없는지, 많으면 좌우 스크롤·클릭 재편집·우클릭 삭제 확인(수동)

- [ ] **Step 5: 커밋**

```bash
git add Sources/SnapScreenKit/Home/HomeView.swift
git commit -m "$(cat <<'EOF'
feat: 홈 창 최근 캡처를 가로 슬라이드로 (세로 빈 공간 제거)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: 문서 + v0.10.1 범프 + PR

**Files:**
- Modify: `docs/manual-test-checklist.md`, `README.md`
- Modify: `Sources/SnapScreenKit/Support/AppInfo.swift`, `Resources/Info.plist`

- [ ] **Step 1: 체크리스트 §19 보강**

`docs/manual-test-checklist.md`의 "## 19. 최근 캡처 (히스토리)" 섹션 목록 끝에 항목 추가:

```markdown
- [ ] 최근 캡처가 가로 한 줄로 표시되고, 많으면 좌우로 스크롤되며 창 세로에 큰 빈 공간이 없다
```

- [ ] **Step 2: 버전 범프**

- `Sources/SnapScreenKit/Support/AppInfo.swift`: `version = "0.10.1"`
- Info.plist:
```bash
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString 0.10.1" Resources/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion 17" Resources/Info.plist
```

- [ ] **Step 3: README 갱신**

`README.md`를 Read 후, 최근 캡처 갤러리 설명 문구에 "가로 슬라이드" 취지를 자연스럽게 반영(예: "홈 창에서 가로로 넘겨보고 다시 열기"). 과한 변경 금지.

- [ ] **Step 4: 최종 검증**

```bash
swift test 2>&1 | grep -E "Executed [0-9]+ tests" | tail -1        # 78 PASS
rm -rf .build && swift build 2>&1 | grep -ci warning               # 0
Scripts/bundle.sh release                                          # OK
file -I README.md docs/manual-test-checklist.md                    # utf-8
/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist  # 0.10.1
/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" Resources/Info.plist              # 17
```

- [ ] **Step 5: Commit + Push + PR**

```bash
git add docs/ README.md Sources/ Resources/
git commit -m "$(cat <<'EOF'
chore: 홈 슬라이드 문서 + v0.10.1 버전 범프

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
git push -u origin feat/home-history-slider
gh pr create --title "feat: 홈 창 최근 캡처 가로 슬라이드" --body "$(cat <<'EOF'
## Summary
- 홈 창 최근 캡처를 고정 높이 세로 그리드 → 가로 한 줄 슬라이드로 변경 (항목이 적어도 세로 빈 공간이 크게 남던 문제 해결)
- `ScrollView(.horizontal)` + `LazyHStack`, 썸네일 120×78 고정, 섹션 높이 86pt
- 클릭 재편집·우클릭 삭제·툴팁은 그대로
- v0.10.1 범프

## 설계/계획
- Spec: `docs/superpowers/specs/2026-07-10-home-history-slider-design.md`
- Plan: `docs/superpowers/plans/2026-07-10-home-history-slider.md`

## Test plan
- [x] clean 빌드 경고 0, 기존 78 테스트 통과
- [ ] 수동: 가로 한 줄 표시·좌우 스크롤·세로 빈 공간 없음·클릭 재편집·삭제 (checklist §19)
EOF
)"
```
`--reviewer` 플래그 쓰지 말 것.

## 실행 순서와 검증 한계

- Task 1(UI) → 2(문서·범프·PR).
- SwiftUI 레이아웃이라 자동 테스트 불가 → 수동 §19. 기존 78개 테스트는 회귀 없음만 확인.
- 릴리스(`make release VERSION=v0.10.1`)는 PR 머지 후 별도.
