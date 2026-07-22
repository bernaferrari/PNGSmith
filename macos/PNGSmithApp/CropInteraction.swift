import AppKit
import SwiftUI

enum CropHandle: CaseIterable {
    case topLeading, top, topTrailing, leading, trailing, bottomLeading, bottom, bottomTrailing

    static let edges: [Self] = [.top, .leading, .trailing, .bottom]
    static let corners: [Self] = [.topLeading, .topTrailing, .bottomLeading, .bottomTrailing]

    var isCorner: Bool {
        switch self {
        case .topLeading, .topTrailing, .bottomLeading, .bottomTrailing: true
        default: false
        }
    }

    var cursor: NSCursor {
        if #available(macOS 15.0, *) {
            let position: NSCursor.FrameResizePosition = switch self {
            case .topLeading: .topLeft
            case .top: .top
            case .topTrailing: .topRight
            case .leading: .left
            case .trailing: .right
            case .bottomLeading: .bottomLeft
            case .bottom: .bottom
            case .bottomTrailing: .bottomRight
            }
            return .frameResize(position: position, directions: .all)
        }

        return switch self {
        case .top, .bottom: .resizeUpDown
        case .leading, .trailing: .resizeLeftRight
        case .topLeading, .topTrailing, .bottomLeading, .bottomTrailing: .crosshair
        }
    }
}

@MainActor
final class CropEditHistory: ObservableObject {
    @Published private(set) var revision = 0
    private var edit: Binding<CanvasEdit>?
    private weak var undoManager: UndoManager?

    func connect(edit: Binding<CanvasEdit>, undoManager: UndoManager?) {
        self.edit = edit
        self.undoManager = undoManager
    }

    func disconnect() {
        undoManager?.removeAllActions(withTarget: self)
        edit = nil
        undoManager = nil
    }

    func record(before: CanvasEdit, actionName: String) {
        guard let edit, before != edit.wrappedValue, let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { history in
            history.restore(before, actionName: actionName)
        }
        undoManager.setActionName(actionName)
        revision &+= 1
    }

    private func restore(_ value: CanvasEdit, actionName: String) {
        guard let edit, let undoManager else { return }
        let inverse = edit.wrappedValue
        edit.wrappedValue = value
        undoManager.registerUndo(withTarget: self) { history in
            history.restore(inverse, actionName: actionName)
        }
        undoManager.setActionName(actionName)
        revision &+= 1
    }
}
