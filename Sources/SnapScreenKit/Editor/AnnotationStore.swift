import Foundation
import CoreGraphics

public final class AnnotationStore {
    public private(set) var annotations: [Annotation] = []
    private var undoStack: [[Annotation]] = []
    private var redoStack: [[Annotation]] = []

    public init() {}

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    public func add(_ annotation: Annotation) {
        snapshot()
        annotations.append(annotation)
    }

    public func remove(id: UUID) {
        guard annotations.contains(where: { $0.id == id }) else { return }
        snapshot()
        annotations.removeAll { $0.id == id }
    }

    public func translate(id: UUID, by delta: CGVector) {
        guard let i = annotations.firstIndex(where: { $0.id == id }) else { return }
        snapshot()
        annotations[i].kind = annotations[i].kind.translated(by: delta)
    }

    public func undo() {
        guard let prev = undoStack.popLast() else { return }
        redoStack.append(annotations)
        annotations = prev
    }

    public func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(annotations)
        annotations = next
    }

    public var nextStepNumber: Int {
        let numbers = annotations.compactMap { a -> Int? in
            if case .stepBadge(_, let n, _) = a.kind { return n }
            return nil
        }
        return (numbers.max() ?? 0) + 1
    }

    private func snapshot() {
        undoStack.append(annotations)
        redoStack.removeAll()
    }
}
