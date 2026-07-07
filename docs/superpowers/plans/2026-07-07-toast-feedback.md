# 편집기 인라인 토스트 피드백 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 편집기 캔버스 위에 짧은 인라인 토스트를 띄워 복사/OCR 결과를 확실히 피드백한다.

**Architecture:** `ToastView`(반투명 pill NSView)를 `CanvasView.showToast(_:)`가 캔버스 하단 중앙에 추가하고 페이드인→유지→페이드아웃 후 제거한다. `EditorWindowController`의 복사/OCR 성공·안내 경로가 이를 호출한다. 하드 실패는 기존 `Notifier.alertFailure` 유지.

**Tech Stack:** AppKit(NSView, NSAnimationContext), Swift.

---

## 파일 구조

| 파일 | 책임 | 상태 |
|---|---|---|
| `Editor/ToastView.swift` | 반투명 pill 메시지 뷰 | 신규 |
| `Editor/CanvasView.swift` | `showToast(_:)` 표시/자동 제거 | 수정 |
| `Editor/EditorWindowController.swift` | 복사/OCR 성공·안내 시 `canvas.showToast` 호출 | 수정 |
| `docs/manual-test-checklist.md`, `README.md`, `Support/AppInfo.swift`, `Resources/Info.plist` | 문서·버전 | 수정 |

토스트는 시각·타이머 동작이라 자동 단위 테스트 대상이 아니다. 검증은 빌드(경고 0)·기존 테스트 회귀 없음(62 유지)·수동 체크리스트로 한다.

---

### Task 1: ToastView + CanvasView.showToast

**Files:**
- Create: `Sources/SnapScreenKit/Editor/ToastView.swift`
- Modify: `Sources/SnapScreenKit/Editor/CanvasView.swift`

- [ ] **Step 1: ToastView 작성**

`Sources/SnapScreenKit/Editor/ToastView.swift`:

```swift
import AppKit

/// 편집기 캔버스 위에 잠깐 뜨는 반투명 pill 메시지 뷰.
@MainActor
final class ToastView: NSView {
    private let label = NSTextField(labelWithString: "")

    init(message: String) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.75).cgColor
        layer?.cornerRadius = 10
        label.stringValue = message
        label.textColor = .white
        label.font = .boldSystemFont(ofSize: 13)
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize {
        let s = label.intrinsicContentSize
        return NSSize(width: min(s.width, 360) + 32, height: s.height + 16)
    }

    override func layout() {
        super.layout()
        label.frame = bounds.insetBy(dx: 16, dy: 8)
    }
}
```

- [ ] **Step 2: CanvasView에 showToast 추가**

`CanvasView`에 프로퍼티 추가(`onRequestOCR` 근처):

```swift
    private var toast: ToastView?
```

메서드 추가(예: `cancelCropIfActive()` 근처, 클래스 내):

```swift
    /// 캔버스 하단 중앙에 잠깐 토스트를 표시한다 (복사/OCR 피드백). 알림 권한과 무관하게 항상 보인다.
    func showToast(_ message: String) {
        toast?.removeFromSuperview()
        let t = ToastView(message: message)
        t.translatesAutoresizingMaskIntoConstraints = false
        t.alphaValue = 0
        addSubview(t)
        NSLayoutConstraint.activate([
            t.centerXAnchor.constraint(equalTo: centerXAnchor),
            t.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -24)
        ])
        toast = t
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            t.animator().alphaValue = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self, weak t] in
            guard let t, t.superview != nil else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.3
                t.animator().alphaValue = 0
            }, completionHandler: {
                t.removeFromSuperview()
                if self?.toast === t { self?.toast = nil }
            })
        }
    }
```

- [ ] **Step 3: 빌드**

Run: `rm -rf .build && swift build 2>&1 | grep -ci warning`
Expected: `0`

- [ ] **Step 4: 커밋**

```bash
git add Sources/SnapScreenKit/Editor/ToastView.swift Sources/SnapScreenKit/Editor/CanvasView.swift
git commit -m "feat: 편집기 인라인 토스트 뷰 + showToast"
```

---

### Task 2: 통합 + 문서 + v0.8.1 범프 + PR

**Files:**
- Modify: `Sources/SnapScreenKit/Editor/EditorWindowController.swift`
- Modify: `docs/manual-test-checklist.md`, `README.md`, `Sources/SnapScreenKit/Support/AppInfo.swift`, `Resources/Info.plist`

- [ ] **Step 1: copyMerged에 토스트 추가**

`copyMerged(_:)`를 아래로 교체(현재는 `ClipboardWriter.write` 후 아무 피드백 없음):

```swift
    @objc public func copyMerged(_ sender: Any?) {
        guard let image = flattened() else { return }
        if ClipboardWriter.write(image, scale: result.scale) {
            canvas.showToast("이미지를 복사했습니다")
        }
    }
```

- [ ] **Step 2: performOCR의 성공/안내를 토스트로 전환**

`performOCR()`의 완료 스위치에서 성공·텍스트 없음 경로를 `Notifier.show` → `canvas.showToast`로 교체(실패는 `Notifier.alertFailure` 유지):

```swift
            switch result {
            case .success(let text) where text.isEmpty:
                self.canvas.showToast("인식된 텍스트가 없습니다")
            case .success(let text):
                ClipboardWriter.write(text: text)
                self.canvas.showToast("\(text.count)자를 복사했습니다")
            case .failure(let error):
                Notifier.alertFailure(title: "OCR 실패", body: error.localizedDescription)
            }
```

(주의: 이 클로저는 이미 `guard let self else { return }`로 self를 언래핑하므로 `self.canvas` 접근이 가능하다. `isRecognizing = false` 리셋은 스위치 앞에 그대로 둔다.)

- [ ] **Step 3: 체크리스트에 "17. 복사 피드백 토스트" 추가**

`docs/manual-test-checklist.md` 끝에:

```markdown
## 17. 복사 피드백 토스트

- [ ] OCR로 텍스트를 복사하면 캔버스 하단에 "N자를 복사했습니다" 토스트가 뜨고 잠시 후 사라진다
- [ ] 텍스트 없는 이미지 OCR 시 "인식된 텍스트가 없습니다" 토스트가 뜬다
- [ ] ⌘C로 이미지를 복사하면 "이미지를 복사했습니다" 토스트가 뜬다
- [ ] 연속으로 복사하면 이전 토스트가 새 토스트로 교체된다
- [ ] OCR 실패 시에는 기존처럼 beep + 시스템 알림이 뜬다(토스트 아님)
```

- [ ] **Step 4: 버전 범프**

- `Sources/SnapScreenKit/Support/AppInfo.swift`: `version = "0.8.1"`
- Info.plist:
```bash
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString 0.8.1" Resources/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion 11" Resources/Info.plist
```

- [ ] **Step 5: README 갱신**

`README.md`를 Read 후, OCR/복사 관련 기능 설명에 "복사·추출 시 편집기 내 토스트로 피드백" 취지의 짧은 문구를 자연스러운 위치에 추가(과한 변경 금지).

- [ ] **Step 6: 최종 검증**

```bash
swift test 2>&1 | grep -E "Executed [0-9]+ tests" | tail -1        # 62 유지
rm -rf .build && swift build 2>&1 | grep -ci warning               # 0
Scripts/bundle.sh release                                          # OK
file -I README.md docs/manual-test-checklist.md                    # utf-8
/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist  # 0.8.1
/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" Resources/Info.plist              # 11
```

- [ ] **Step 7: Commit + Push + PR**

```bash
git add Sources/ docs/ README.md Resources/
git commit -m "feat: 복사/OCR 피드백을 인라인 토스트로 + v0.8.1"
git push -u origin feat/toast-feedback
gh pr create --title "feat: 편집기 인라인 토스트 피드백" --body "$(cat <<'EOF'
## Summary
- OCR 복사·이미지 복사(⌘C) 시 편집기 캔버스에 인라인 토스트로 피드백 (시스템 알림이 편집 중 놓치기 쉽고 ad-hoc 서명으로 안 뜰 수 있던 문제 해결)
- `ToastView`(반투명 pill) + `CanvasView.showToast`
- OCR 성공/텍스트 없음/이미지 복사 → 토스트, 하드 실패(OCR/저장)는 기존 beep+알림 유지
- v0.8.1 범프

## 설계/계획
- Spec: `docs/superpowers/specs/2026-07-07-toast-feedback-design.md`
- Plan: `docs/superpowers/plans/2026-07-07-toast-feedback.md`

## Test plan
- [x] clean 빌드 경고 0, 기존 62 테스트 통과
- [ ] 수동: OCR/이미지 복사 토스트, 텍스트 없음, 연속 교체, 실패 시 알림 유지 (checklist §17)
EOF
)"
```

커밋 메시지 끝에 빈 줄 후 `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>` 추가. `--reviewer` 플래그 쓰지 말 것.

## 실행 순서와 검증 한계

- Task 1(뷰+표시) → 2(통합·범프·PR).
- 토스트는 GUI/타이머라 자동 테스트 불가 → 수동 §17. 기존 단위 테스트(62)는 회귀 없음만 확인.
- 릴리스(`make release VERSION=v0.8.1`)는 PR 머지 후 별도.
