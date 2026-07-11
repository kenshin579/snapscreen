# 편집기 리디자인 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 편집기를 `[좌측 도구 레일 | 캔버스 | 우측 인스펙터]` + 타이틀바 버튼 구조로 재구성하고, 신규 상태 `lineWidth`/`shadowEnabled`(per-annotation)와 핸드오프 팔레트(동적 라이트/다크)·캔버스 배경/그림자를 도입한다. 기존 동작·단축키·내보내기 결과물(주석 그림자 제외)은 유지.

**Architecture:** 3개 태스크 — (1) 모델·렌더러 코어(EditorState/Annotation/PaletteColor/AnnotationRenderer), (2) 캔버스(CanvasView: 굵기·그림자 배선 + 배경/이미지 그림자), (3) UI 레이아웃(신규 3뷰 + EditorWindowController 재구성, ToolbarView 삭제). 각 태스크는 빌드·테스트 green을 유지한다. 캔버스는 AppKit `CanvasView` 유지, 레일/인스펙터/타이틀바 버튼은 `NSHostingView`.

**Tech Stack:** Swift, SwiftUI, AppKit(NSWindow/NSTitlebarAccessoryViewController/NSGradient/CGContext), CoreImage.

**참고 스펙:** `docs/superpowers/specs/2026-07-11-snapscreen-editor-redesign-design.md`
**디자인 값 출처:** `docs/design/design_handoff_snapscreen_redesign/README.md` §2

**사전 확인된 사실:**
- `AnnotationStore.canUndo`/`canRedo` 이미 존재 — 추가 불필요.
- 기존 테스트는 `Annotation(kind:)`만 사용, 팔레트 케이스·색 픽셀 미검증 → `shadowEnabled`를 기본값과 함께 추가하면 테스트 수정 불필요. (`swift test`로 확인만.)
- `NSColor(hex:alpha:)` convenience init은 `DesignTokens.swift`(동일 모듈)에 이미 존재 — 재사용.

---

## File Structure

- **Modify** `Sources/SnapScreenKit/Editor/EditorState.swift` — `lineWidth`, `shadowEnabled` (Task 1).
- **Modify** `Sources/SnapScreenKit/Editor/Annotation.swift` — `Annotation.shadowEnabled`, `PaletteColor` 케이스 재작업 (Task 1).
- **Modify** `Sources/SnapScreenKit/Editor/AnnotationRenderer.swift` — `nsColor` 동적, 그림자, badge 대비 (Task 1).
- **Modify** `Sources/SnapScreenKit/Editor/CanvasView.swift` — 굵기/그림자 배선, 배경 그라디언트+이미지 그림자 (Task 2).
- **Create** `Sources/SnapScreenKit/Editor/ToolRailView.swift`, `InspectorView.swift`, `EditorTitlebarButtons.swift` (Task 3).
- **Modify** `Sources/SnapScreenKit/Editor/EditorWindowController.swift` — 레이아웃/타이틀바/파일명 (Task 3).
- **Delete** `Sources/SnapScreenKit/Editor/ToolbarView.swift` (Task 3).

---

## Task 1: 모델 & 렌더러 코어

**Files:** `EditorState.swift`, `Annotation.swift`, `AnnotationRenderer.swift`

- [ ] **Step 1: `EditorState.swift` — 필드 2개 추가**

`EditorState` 클래스 본문(`@Published public var color` 다음)에 추가:
```swift
    @Published public var lineWidth: CGFloat = 3       // 인스펙터 슬라이더 (points, pre-scale)
    @Published public var shadowEnabled: Bool = true   // 인스펙터 토글
```
파일 상단 import에 `CoreGraphics`가 없으면 `import CoreGraphics` 추가(현재 `import Foundation`만 있으면 `CGFloat` 위해 필요). 확인 후 없으면 추가.

- [ ] **Step 2: `Annotation.swift` — `shadowEnabled` 필드 + `PaletteColor` 케이스 재작업**

`PaletteColor` 케이스 교체:
```swift
public enum PaletteColor: String, CaseIterable, Equatable, Codable {
    case red, orange, yellow, green, blue, label
}
```

`Annotation` 구조체에 `shadowEnabled` 추가 (기존 필드/init 확장, 기본값으로 기존 호출부·테스트 호환):
```swift
public struct Annotation: Equatable, Identifiable {
    public let id: UUID
    public var kind: AnnotationKind
    public var color: PaletteColor
    public var lineWidth: CGFloat
    public var shadowEnabled: Bool

    public init(id: UUID = UUID(), kind: AnnotationKind,
                color: PaletteColor = .red, lineWidth: CGFloat = 4,
                shadowEnabled: Bool = false) {
        self.id = id
        self.kind = kind
        self.color = color
        self.lineWidth = lineWidth
        self.shadowEnabled = shadowEnabled
    }
}
```

- [ ] **Step 3: `AnnotationRenderer.swift` — 동적 nsColor + 그림자 + badge 대비**

3-1. `PaletteColor.nsColor` 확장을 동적 라이트/다크로 교체:
```swift
public extension PaletteColor {
    var nsColor: NSColor {
        func dyn(_ light: UInt32, _ dark: UInt32) -> NSColor {
            NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                    ? NSColor(hex: dark) : NSColor(hex: light)
            }
        }
        switch self {
        case .red:    return dyn(0xFF3B30, 0xFF453A)
        case .orange: return dyn(0xFF9500, 0xFF9F0A)
        case .yellow: return dyn(0xFFCC00, 0xFFD60A)
        case .green:  return dyn(0x34C759, 0x30D158)
        case .blue:   return dyn(0x007AFF, 0x0A84FF)
        case .label:  return dyn(0x1D1D1F, 0xF5F5F7)
        }
    }
}
```

3-2. `draw(_ annotation:...)` 단일 그리기 함수를 그림자 래핑으로 감싼다. 기존 함수 본문(색 계산 + switch)은 유지하고 앞뒤에 그림자 처리 추가:
```swift
    public static func draw(_ annotation: Annotation, in ctx: CGContext,
                            baseImage: CGImage, scale: CGFloat) {
        // pixelate/blur는 이미지 영역이라 그림자 제외(보안 목적·시각 훼손 방지)
        let castsShadow: Bool = {
            guard annotation.shadowEnabled else { return false }
            switch annotation.kind {
            case .pixelate, .blur: return false
            default: return true
            }
        }()
        if castsShadow {
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -2 * scale),
                          blur: 4 * scale,
                          color: NSColor(white: 0, alpha: 0.35).cgColor)
        }
        let color = annotation.color.nsColor.cgColor
        switch annotation.kind {
        case .arrow(let start, let end):
            drawArrow(from: start, to: end, color: color,
                      lineWidth: annotation.lineWidth, in: ctx)
        case .rectangle(let rect):
            ctx.setStrokeColor(color)
            ctx.setLineWidth(annotation.lineWidth)
            ctx.stroke(rect)
        case .ellipse(let rect):
            ctx.setStrokeColor(color)
            ctx.setLineWidth(annotation.lineWidth)
            ctx.strokeEllipse(in: rect)
        case .text(let origin, let string, let fontSize):
            drawText(string, at: origin, fontSize: fontSize,
                     color: annotation.color.nsColor, in: ctx)
        case .pixelate(let rect):
            if let cached = pixelateCache[annotation.id], cached.rect == rect {
                ctx.draw(cached.image, in: cached.clamped)
            } else if let result = pixelatedImage(from: baseImage, rect: rect, scale: scale) {
                if pixelateCache.count >= 64 { pixelateCache.removeAll() }
                pixelateCache[annotation.id] = (rect, result.image, result.rect)
                ctx.draw(result.image, in: result.rect)
            }
        case .blur(let rect):
            if let cached = pixelateCache[annotation.id], cached.rect == rect {
                ctx.draw(cached.image, in: cached.clamped)
            } else if let result = blurredImage(from: baseImage, rect: rect, scale: scale) {
                if pixelateCache.count >= 64 { pixelateCache.removeAll() }
                pixelateCache[annotation.id] = (rect, result.image, result.rect)
                ctx.draw(result.image, in: result.rect)
            }
        case .stepBadge(let center, let number, let radius):
            drawBadge(number: number, center: center, radius: radius,
                      color: annotation.color.nsColor, in: ctx)
        case .path(let points):
            ctx.setStrokeColor(color)
            ctx.setLineWidth(annotation.lineWidth)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.addPath(PathSmoother.smoothedPath(points))
            ctx.strokePath()
        }
        if castsShadow { ctx.restoreGState() }
    }
```

3-3. `drawBadge`의 글자색 대비를 명도 기반으로 일반화. `attrs`의 `foregroundColor` 라인을 교체:
```swift
            .foregroundColor: color.ks_isLight ? NSColor.black : NSColor.white
```
그리고 파일 하단(다른 함수 밖, 파일 끝)에 헬퍼 추가:
```swift
private extension NSColor {
    /// 배지 글자색 대비용 상대 명도 판정. 동적 색은 현재 NSAppearance 기준으로 해석된다.
    var ks_isLight: Bool {
        guard let c = usingColorSpace(.sRGB) else { return false }
        let lum = 0.299 * c.redComponent + 0.587 * c.greenComponent + 0.114 * c.blueComponent
        return lum > 0.6
    }
}
```

- [ ] **Step 4: 빌드 & 테스트**

Run: `swift build` → `Build complete!`
Run: `swift test` → 88개 통과 (테스트가 새 필드/케이스를 참조 안 하므로 회귀 없음). 만약 깨지는 테스트가 있으면 **원인을 보고**하고 최소 수정.

- [ ] **Step 5: UTF-8 & Commit**

Run: `file -I Sources/SnapScreenKit/Editor/EditorState.swift Sources/SnapScreenKit/Editor/Annotation.swift Sources/SnapScreenKit/Editor/AnnotationRenderer.swift` → 모두 utf-8.
```bash
git add Sources/SnapScreenKit/Editor/EditorState.swift Sources/SnapScreenKit/Editor/Annotation.swift Sources/SnapScreenKit/Editor/AnnotationRenderer.swift
git commit -m "feat: 편집기 상태(lineWidth/shadowEnabled)·팔레트 동적화·주석 그림자 렌더링"
```

---

## Task 2: 캔버스 (굵기/그림자 배선 + 배경/이미지 그림자)

**Files:** `CanvasView.swift`

- [ ] **Step 1: `defaultLineWidth`를 상태 기반으로**

`CanvasView.swift` 라인 72를 교체:
```swift
    private var defaultLineWidth: CGFloat { state.lineWidth * captureScale }
```

- [ ] **Step 2: 주석 생성 4곳에 `shadowEnabled: state.shadowEnabled` 추가**

아래 4개 `Annotation(...)` 생성에 `shadowEnabled: state.shadowEnabled` 인자를 추가한다. (`.path` 분할 재생성 라인 123은 기존 주석 속성 보존이므로 `shadowEnabled: a.shadowEnabled`로 원본 값을 유지.)

2-1. 라인 123 (지우개 분할 재생성):
```swift
                        result.append(Annotation(kind: .path(seg), color: a.color, lineWidth: a.lineWidth, shadowEnabled: a.shadowEnabled))
```
2-2. 라인 237~239 (stepBadge):
```swift
            store.add(Annotation(kind: .stepBadge(center: p, number: store.nextStepNumber,
                                                   radius: badgeRadius),
                                 color: state.color, lineWidth: defaultLineWidth,
                                 shadowEnabled: state.shadowEnabled))
```
2-3. 라인 243 (펜 draft 시작):
```swift
            draft = Annotation(kind: .path([p]), color: state.color, lineWidth: defaultLineWidth,
                               shadowEnabled: state.shadowEnabled)
```
2-4. 라인 351 (도형 draft 생성 `makeDraft`):
```swift
        return Annotation(kind: kind, color: state.color, lineWidth: defaultLineWidth,
                          shadowEnabled: state.shadowEnabled)
```
2-5. 라인 573~575 (텍스트 커밋):
```swift
            store.add(Annotation(kind: .text(origin: origin, string: string,
                                             fontSize: defaultFontSize),
                                 color: state.color, lineWidth: defaultLineWidth,
                                 shadowEnabled: state.shadowEnabled))
```
(정확한 줄은 이동했을 수 있으니 각 `Annotation(` 생성 지점을 grep로 찾아 동일 패턴으로 인자 추가. draft 라인 123의 지우개 분할만 `a.shadowEnabled`, 나머지는 `state.shadowEnabled`.)

- [ ] **Step 3: 배경 그라디언트 + 이미지 드롭섀도 + 외관 변화 재그리기**

3-1. `draw(_ dirtyRect:)`의 배경/이미지 부분(현재 라인 147~153)을 교체. `NSColor.windowBackgroundColor.setFill(); bounds.fill()`를 중립 radial 그라디언트로 바꾸고, **이미지 자신의 알파 모양을 따라** 드롭섀도를 지게 한다(투명 캡처도 안전 — 검정 사각형을 뒤에 깔지 않음). 그림자는 이미지에만 적용되도록 draw 직후 해제:
```swift
        // 중립 배경 (radial 그라디언트)
        let bg = canvasBackgroundGradient()
        bg.draw(in: bounds, relativeCenterPosition: .zero)

        ctx.saveGState()
        ctx.translateBy(x: fitOffset.x, y: fitOffset.y)
        ctx.scaleBy(x: fitScale, y: fitScale)
        ctx.interpolationQuality = .high
        // 이미지 드롭섀도 — 이미지 알파 모양을 따라. 파라미터는 스케일된 CTM 기준이라 fitScale로 나눠 화면 픽셀 기준 유지.
        let fs = max(fitScale, 0.0001)
        ctx.setShadow(offset: CGSize(width: 0, height: -3 / fs), blur: 16 / fs,
                      color: NSColor(white: 0, alpha: 0.28).cgColor)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        ctx.setShadow(offset: .zero, blur: 0, color: nil)   // 이후 주석은 이미지 그림자 상속 안 함
```
(이후 기존 `let toRender = ...` 이하 주석 렌더 루프·`drawOverlays`·`ctx.restoreGState()`는 그대로 유지. 위 `ctx.saveGState()`가 기존 마지막 `ctx.restoreGState()`와 짝을 이룬다.)

3-2. 그라디언트 헬퍼 + 외관 변화 재그리기를 파일 내 적당한 위치(예: `draw` 아래)에 추가:
```swift
    /// 중립 캔버스 배경. 시스템 외관(라이트/다크)에 따라 색을 분기.
    private func canvasBackgroundGradient() -> NSGradient {
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let start = dark ? NSColor(hex: 0x2C3240) : NSColor(hex: 0xE3E6EC)
        let end   = dark ? NSColor(hex: 0x1F2229) : NSColor(hex: 0xD3D7DF)
        return NSGradient(starting: start, ending: end) ?? NSGradient(starting: .windowBackgroundColor, ending: .windowBackgroundColor)!
    }

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true   // 라이트/다크 전환 시 배경 갱신
    }
```

- [ ] **Step 4: 빌드 & 테스트**

Run: `swift build` → 성공.
Run: `swift test` → 88개 통과.

- [ ] **Step 5: UTF-8 & Commit**

`file -I Sources/SnapScreenKit/Editor/CanvasView.swift` → utf-8.
```bash
git add Sources/SnapScreenKit/Editor/CanvasView.swift
git commit -m "feat: 캔버스 선굵기/그림자 상태 배선 + 중립 배경 그라디언트·이미지 드롭섀도"
```

---

## Task 3: UI 레이아웃 (신규 3뷰 + 창 재구성 + ToolbarView 삭제)

**Files:** create `ToolRailView.swift`/`InspectorView.swift`/`EditorTitlebarButtons.swift`, modify `EditorWindowController.swift`, delete `ToolbarView.swift`

- [ ] **Step 1: `ToolRailView.swift` 생성**

```swift
import SwiftUI

/// 편집기 좌측 세로 도구 레일 (폭 52). 9개 주석 도구 + 하단 자르기/텍스트 추출.
@MainActor
public struct ToolRailView: View {
    @ObservedObject var state: EditorState
    @ObservedObject var store: AnnotationStore
    let onCrop: () -> Void
    let onOCR: () -> Void

    public init(state: EditorState, store: AnnotationStore,
                onCrop: @escaping () -> Void, onOCR: @escaping () -> Void) {
        self.state = state
        self.store = store
        self.onCrop = onCrop
        self.onOCR = onOCR
    }

    public var body: some View {
        VStack(spacing: 4) {
            ForEach(EditorTool.allCases) { tool in
                railButton(symbol: tool.symbolName, help: tool.label,
                           selected: state.tool == tool) { state.tool = tool }
            }
            Spacer()
            railButton(symbol: "crop",
                       help: store.annotations.isEmpty ? "자르기 (C)" : "주석을 모두 삭제한 후 자를 수 있습니다",
                       selected: false, disabled: !store.annotations.isEmpty, action: onCrop)
            railButton(symbol: "text.viewfinder", help: "텍스트 추출 (E)",
                       selected: false, action: onOCR)
        }
        .padding(.vertical, 10)
        .frame(width: 52)
        .frame(maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .overlay(alignment: .trailing) { DesignTokens.Colors.hairline.frame(width: 1) }
    }

    private func railButton(symbol: String, help: String, selected: Bool,
                            disabled: Bool = false,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15))
                .foregroundStyle(selected ? Color.white : Color.primary)
                .frame(width: 36, height: 32)
                .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.tool)
                    .fill(selected ? Color.accentColor : Color.clear))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1)
        .help(help)
    }
}
```

- [ ] **Step 2: `InspectorView.swift` 생성**

```swift
import SwiftUI

/// 편집기 우측 인스펙터 (폭 170). 색상·선 굵기·그림자·빠른 작업.
@MainActor
public struct InspectorView: View {
    @ObservedObject var state: EditorState
    let onCrop: () -> Void
    let onOCR: () -> Void

    public init(state: EditorState, onCrop: @escaping () -> Void, onOCR: @escaping () -> Void) {
        self.state = state
        self.onCrop = onCrop
        self.onOCR = onOCR
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 6)

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("색상")
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(PaletteColor.allCases, id: \.self) { swatch($0) }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    sectionLabel("선 굵기")
                    Spacer()
                    Text("\(Int(state.lineWidth))px")
                        .font(.system(size: 11)).monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Slider(value: $state.lineWidth, in: 1...12, step: 1)
            }

            HStack {
                Text("그림자").font(.system(size: 12))
                Spacer()
                Toggle("", isOn: $state.shadowEnabled).labelsHidden()
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                sectionLabel("빠른 작업")
                quickButton("텍스트 추출", action: onOCR)
                quickButton("자르기", action: onCrop)
            }

            Spacer()
        }
        .padding(14)
        .frame(width: 170)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.ultraThinMaterial)
        .overlay(alignment: .leading) { DesignTokens.Colors.hairline.frame(width: 1) }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
    }

    private func swatch(_ color: PaletteColor) -> some View {
        let selected = state.color == color
        return Circle()
            .fill(Color(nsColor: color.nsColor))
            .frame(width: 18, height: 18)
            // 선택 링: 2px 배경색 갭 + 3.5px 액센트 링
            .overlay(Circle().stroke(Color(nsColor: .windowBackgroundColor),
                                     lineWidth: selected ? 2 : 0).padding(-1.5))
            .overlay(Circle().stroke(Color.accentColor,
                                     lineWidth: selected ? 3 : 0).padding(-3.5))
            .contentShape(Circle())
            .onTapGesture { state.color = color }
    }

    private func quickButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 12))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6).padding(.horizontal, 8)
                .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.button)
                    .fill(Color.primary.opacity(0.06)))
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 3: `EditorTitlebarButtons.swift` 생성**

```swift
import SwiftUI

/// 편집기 타이틀바 우측 접근성 뷰: undo/redo/복사/저장.
@MainActor
public struct EditorTitlebarButtons: View {
    @ObservedObject var store: AnnotationStore
    let onUndo: () -> Void
    let onRedo: () -> Void
    let onCopy: () -> Void
    let onSave: () -> Void

    public init(store: AnnotationStore,
                onUndo: @escaping () -> Void, onRedo: @escaping () -> Void,
                onCopy: @escaping () -> Void, onSave: @escaping () -> Void) {
        self.store = store
        self.onUndo = onUndo
        self.onRedo = onRedo
        self.onCopy = onCopy
        self.onSave = onSave
    }

    public var body: some View {
        HStack(spacing: 8) {
            Button(action: onUndo) { Image(systemName: "arrow.uturn.backward") }
                .buttonStyle(.plain)
                .disabled(!store.canUndo).opacity(store.canUndo ? 1 : 0.35)
                .help("실행 취소 (⌘Z)")
            Button(action: onRedo) { Image(systemName: "arrow.uturn.forward") }
                .buttonStyle(.plain)
                .disabled(!store.canRedo).opacity(store.canRedo ? 1 : 0.35)
                .help("실행 복귀 (⇧⌘Z)")
            Button(action: onCopy) { Text("복사").font(.system(size: 12)) }
                .help("클립보드로 복사 (⌘C)")
            Button(action: onSave) { Text("저장").font(.system(size: 12, weight: .semibold)) }
                .buttonStyle(.borderedProminent)
                .help("파일로 저장 (⌘S)")
        }
        .padding(.horizontal, 12)
    }
}
```

- [ ] **Step 4: `EditorWindowController.swift` — init 뷰 구성 + resize + 파일명 교체**

파일 전체를 아래로 교체 (기존 액션 메서드·crop·OCR·windowWillClose는 유지, 뷰 구성/사이징만 변경):

```swift
import AppKit
import Combine
import SwiftUI

@MainActor
public final class EditorWindowController: NSWindowController, NSWindowDelegate {
    private let result: CaptureResult
    private var image: CGImage
    private let settings: SettingsStore
    private let store = AnnotationStore()
    private let state = EditorState()
    private var canvas: CanvasView!
    private var onClose: (() -> Void)?
    private let policyManager: ActivationPolicyManager?
    private var toolCancellable: AnyCancellable?
    private var isRecognizing = false

    private let railWidth: CGFloat = 52
    private let inspectorWidth: CGFloat = 170

    public init(result: CaptureResult, settings: SettingsStore,
                policyManager: ActivationPolicyManager? = nil,
                onClose: (() -> Void)? = nil) {
        self.result = result
        self.image = result.image
        self.settings = settings
        self.policyManager = policyManager
        self.onClose = onClose

        let pointSize = CGSize(width: CGFloat(result.image.width) / result.scale,
                               height: CGFloat(result.image.height) / result.scale)
        let maxSize = NSScreen.main.map { CGSize(width: $0.visibleFrame.width * 0.8,
                                                 height: $0.visibleFrame.height * 0.8) }
            ?? CGSize(width: 1200, height: 800)
        let chrome = railWidth + inspectorWidth
        let fit = min(1, (maxSize.width - chrome) / pointSize.width, maxSize.height / pointSize.height)
        let canvasSize = CGSize(width: pointSize.width * fit, height: pointSize.height * fit)

        let window = NSWindow(contentRect: CGRect(origin: .zero, size: canvasSize),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        // 예정 파일명 (열릴 때 1회 생성) — 중앙 타이틀
        window.title = FilenameFormatter(prefix: settings.filenamePrefix.isEmpty ? "snapscreen"
                                         : settings.filenamePrefix).filename(for: Date())
        window.isReleasedWhenClosed = false
        super.init(window: window)

        window.setContentSize(CGSize(width: canvasSize.width + chrome, height: canvasSize.height))
        window.contentAspectRatio = .zero
        window.minSize = NSSize(width: chrome + 240, height: 220)

        canvas = CanvasView(image: self.image, captureScale: result.scale,
                            store: store, state: state)
        canvas.onCropConfirmed = { [weak self] rect in self?.applyCrop(rect) }
        canvas.onRequestOCR = { [weak self] in self?.performOCR() }

        let rail = NSHostingView(rootView: ToolRailView(
            state: state, store: store,
            onCrop: { [weak self] in self?.canvas.beginCrop() },
            onOCR: { [weak self] in self?.performOCR() }))
        let inspector = NSHostingView(rootView: InspectorView(
            state: state,
            onCrop: { [weak self] in self?.canvas.beginCrop() },
            onOCR: { [weak self] in self?.performOCR() }))

        let container = NSView()
        for v in [rail, canvas!, inspector] {
            v.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(v)
        }
        NSLayoutConstraint.activate([
            rail.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            rail.topAnchor.constraint(equalTo: container.topAnchor),
            rail.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            rail.widthAnchor.constraint(equalToConstant: railWidth),

            canvas.leadingAnchor.constraint(equalTo: rail.trailingAnchor),
            canvas.topAnchor.constraint(equalTo: container.topAnchor),
            canvas.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            inspector.leadingAnchor.constraint(equalTo: canvas.trailingAnchor),
            inspector.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            inspector.topAnchor.constraint(equalTo: container.topAnchor),
            inspector.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            inspector.widthAnchor.constraint(equalToConstant: inspectorWidth)
        ])
        window.contentView = container

        // 타이틀바 우측 버튼 (undo/redo/복사/저장)
        let titleButtons = NSHostingView(rootView: EditorTitlebarButtons(
            store: store,
            onUndo: { [weak self] in self?.undoAction(nil) },
            onRedo: { [weak self] in self?.redoAction(nil) },
            onCopy: { [weak self] in self?.copyMerged(nil) },
            onSave: { [weak self] in self?.saveImage(nil) }))
        titleButtons.frame.size = titleButtons.fittingSize
        let accessory = NSTitlebarAccessoryViewController()
        accessory.view = titleButtons
        accessory.layoutAttribute = .trailing
        window.addTitlebarAccessoryViewController(accessory)

        window.delegate = self
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(canvas)
        policyManager?.register(window)
        NSApp.activate(ignoringOtherApps: true)

        // 도구 전환 시 진행 중 crop/erase 자동 취소 (기존 유지)
        toolCancellable = state.$tool.sink { [weak self] _ in
            self?.canvas.cancelCropIfActive()
            self?.canvas.cancelEraseIfActive()
            self?.canvas.needsDisplay = true
            if let canvas = self?.canvas { canvas.window?.invalidateCursorRects(for: canvas) }
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    public func windowWillClose(_ notification: Notification) {
        if let window { policyManager?.unregister(window) }
        onClose?()
        onClose = nil
    }

    private func flattened() -> CGImage? {
        FlattenRenderer.flatten(image: image, annotations: store.annotations, scale: result.scale)
    }

    private func applyCrop(_ rect: CGRect) {
        guard let cropped = ImageCropper.crop(image, toBottomLeftRect: rect) else { return }
        image = cropped
        canvas.replaceImage(cropped)
        resizeWindowToImage()
    }

    /// 현재 이미지 비율에 맞게 창 content 크기 재조정 (init 사이징 규칙과 동일, 레일+인스펙터 폭 포함)
    private func resizeWindowToImage() {
        guard let window else { return }
        let pointSize = CGSize(width: CGFloat(image.width) / result.scale,
                               height: CGFloat(image.height) / result.scale)
        let maxSize = NSScreen.main.map { CGSize(width: $0.visibleFrame.width * 0.8,
                                                 height: $0.visibleFrame.height * 0.8) }
            ?? CGSize(width: 1200, height: 800)
        let chrome = railWidth + inspectorWidth
        let fit = min(1, (maxSize.width - chrome) / pointSize.width, maxSize.height / pointSize.height)
        let canvasSize = CGSize(width: pointSize.width * fit, height: pointSize.height * fit)
        window.setContentSize(CGSize(width: canvasSize.width + chrome, height: canvasSize.height))
    }

    // MARK: - 메인 메뉴 액션 (MainMenuBuilder의 nil-target 셀렉터가 응답 체인으로 도달)

    @objc public func copyMerged(_ sender: Any?) {
        guard let image = flattened() else { return }
        if ClipboardWriter.write(image, scale: result.scale) {
            canvas.showToast("이미지를 복사했습니다")
        }
    }

    @objc public func saveImage(_ sender: Any?) {
        guard let image = flattened() else { return }
        switch FileSaver(settings: settings).save(image, scale: result.scale) {
        case .saved:
            window?.close()
        case .savedToFallback(let url):
            Notifier.show(title: "저장 위치 폴백", body: "데스크탑에 저장했습니다: \(url.lastPathComponent)")
            window?.close()
        case .failed(let error):
            Notifier.alertFailure(title: "저장 실패", body: error.localizedDescription)
        }
    }

    @objc public func performOCR() {
        guard !isRecognizing else { return }
        isRecognizing = true
        TextRecognizer.recognize(image) { [weak self] result in
            guard let self else { return }
            self.isRecognizing = false
            switch result {
            case .success(let text) where text.isEmpty:
                self.canvas.showToast("인식된 텍스트가 없습니다")
            case .success(let text):
                ClipboardWriter.write(text: text)
                self.canvas.showToast("\(text.count)자를 복사했습니다")
            case .failure(let error):
                Notifier.alertFailure(title: "OCR 실패", body: error.localizedDescription)
            }
        }
    }

    @objc public func undoAction(_ sender: Any?) {
        store.undo()
        canvas.needsDisplay = true
    }

    @objc public func redoAction(_ sender: Any?) {
        store.redo()
        canvas.needsDisplay = true
    }
}
```

- [ ] **Step 5: `ToolbarView.swift` 삭제**

```bash
git rm Sources/SnapScreenKit/Editor/ToolbarView.swift
```

- [ ] **Step 6: 빌드 & 테스트 & 스모크**

Run: `swift build` → 성공 (ToolbarView 참조가 남아있지 않은지 확인).
Run: `swift test` → 88개 통과.
Run: `Scripts/run.sh` → 크래시 없이 실행. (편집기는 캡처 후에 열리므로, 실행/크래시 여부만 확인. 캡처는 화면 권한이 필요할 수 있음 — 실행만 확인되면 됨.) 확인 후 `pkill -f "build/SnapScreen.app"`.

- [ ] **Step 7: UTF-8 & Commit**

`file -I` 신규 3파일 + EditorWindowController → utf-8.
```bash
git add Sources/SnapScreenKit/Editor/ToolRailView.swift Sources/SnapScreenKit/Editor/InspectorView.swift Sources/SnapScreenKit/Editor/EditorTitlebarButtons.swift Sources/SnapScreenKit/Editor/EditorWindowController.swift
git commit -m "feat: 편집기 레일|캔버스|인스펙터 레이아웃 + 타이틀바 버튼 (ToolbarView 대체)"
```

---

## Self-Review (스펙 대조)

- `EditorState.lineWidth`/`shadowEnabled` → Task 1 Step 1 ✓
- `Annotation.shadowEnabled` (기본값, 테스트 호환) → Task 1 Step 2 ✓
- `PaletteColor` red/orange/yellow/green/blue/label + 동적 nsColor → Task 1 Step 2·3 ✓
- 그림자 렌더(도형만, pixelate/blur 제외) → Task 1 Step 3-2 ✓
- badge 대비 명도 기반 → Task 1 Step 3-3 ✓
- 캔버스 lineWidth from state + shadowEnabled 구움 → Task 2 Step 1·2 ✓
- 캔버스 중립 그라디언트 배경 + 이미지 드롭섀도 + 외관 전환 재그리기 → Task 2 Step 3 ✓
- 좌측 레일(9도구+crop/OCR, crop 비활성) → Task 3 Step 1 ✓
- 우측 인스펙터(색/굵기/그림자/빠른작업) → Task 3 Step 2 ✓
- 타이틀바 버튼(undo/redo/복사/저장, redo 비활성) → Task 3 Step 3·4 ✓
- 창 레이아웃 레일|캔버스|인스펙터 + 파일명 타이틀 → Task 3 Step 4 ✓
- 메인 메뉴 셀렉터·crop 리사이즈·toolCancellable 유지 → Task 3 Step 4 (본문 유지) ✓
- ToolbarView 삭제 → Task 3 Step 5 ✓
- 내보내기 결과물 배경/캔버스그림자 미포함(FlattenRenderer 미변경) / 주석 그림자 포함(AnnotationRenderer 공용) → 설계상 보장 ✓

## 완료 기준

- 파일 수정/신설/삭제, `swift build`/`swift test`(88개) 통과.
- `Scripts/run.sh` 실행 스모크.
- **육안 검증(사용자)**: 레일 도구 선택, 인스펙터 색/굵기(px 표시)/그림자 토글, 타이틀바 undo/redo(비활성 opacity)/복사/저장, 캔버스 중립 배경+이미지 그림자, 라이트/다크, 파일명 타이틀. **회귀**: 9종 주석·crop(주석 있을 때 비활성)·OCR·undo/redo·복사·저장·펜·지우개·번호배지 대비·주석 그림자가 저장 결과물에 포함.
- 한글 소스 UTF-8.

## 다음 단계

편집기 완료 후 마지막 하위 프로젝트 **설정 리디자인**(grouped Form → 사이드바 2-pane).
