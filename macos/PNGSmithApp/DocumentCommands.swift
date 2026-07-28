import SwiftUI

struct PNGSmithDocumentActions {
    let canCycle: Bool
    let canClose: Bool
    let selectPrevious: () -> Void
    let selectNext: () -> Void
    let closeSelected: () -> Void
}

private struct PNGSmithDocumentActionsKey: FocusedValueKey {
    typealias Value = PNGSmithDocumentActions
}

extension FocusedValues {
    var pngsmithDocumentActions: PNGSmithDocumentActions? {
        get { self[PNGSmithDocumentActionsKey.self] }
        set { self[PNGSmithDocumentActionsKey.self] = newValue }
    }
}

@MainActor
final class PNGSmithClipboardCommandRouter {
    static let shared = PNGSmithClipboardCommandRouter()

    private final class Registration {
        weak var window: NSWindow?
        var canCopy = false
        var copy: () -> Void = {}
    }

    private var registrations: [ObjectIdentifier: Registration] = [:]

    func update(window: NSWindow, canCopy: Bool, copy: @escaping () -> Void) {
        removeReleasedWindows()
        let key = ObjectIdentifier(window)
        let registration = registrations[key] ?? Registration()
        registration.window = window
        registration.canCopy = canCopy
        registration.copy = copy
        registrations[key] = registration
    }

    func remove(window: NSWindow) {
        registrations.removeValue(forKey: ObjectIdentifier(window))
    }

    func canCopy(in window: NSWindow?) -> Bool {
        guard let window else { return false }
        return registrations[ObjectIdentifier(window)]?.canCopy == true
    }

    @discardableResult
    func performCopy(in window: NSWindow?) -> Bool {
        guard let window,
              let registration = registrations[ObjectIdentifier(window)],
              registration.canCopy
        else { return false }
        registration.copy()
        return true
    }

    private func removeReleasedWindows() {
        registrations = registrations.filter { $0.value.window != nil }
    }
}

struct PNGSmithClipboardCommandHost: NSViewRepresentable {
    let canCopy: Bool
    let copy: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WindowTrackingView {
        let view = WindowTrackingView()
        view.windowDidChange = { [weak coordinator = context.coordinator] window in
            coordinator?.move(to: window)
        }
        return view
    }

    func updateNSView(_ view: WindowTrackingView, context: Context) {
        context.coordinator.canCopy = canCopy
        context.coordinator.copy = copy
        context.coordinator.move(to: view.window)
    }

    static func dismantleNSView(_ view: WindowTrackingView, coordinator: Coordinator) {
        coordinator.move(to: nil)
    }

    @MainActor
    final class Coordinator {
        weak var window: NSWindow?
        var canCopy = false
        var copy: () -> Void = {}

        func move(to newWindow: NSWindow?) {
            if window !== newWindow, let window {
                PNGSmithClipboardCommandRouter.shared.remove(window: window)
            }
            window = newWindow
            guard let newWindow else { return }
            PNGSmithClipboardCommandRouter.shared.update(
                window: newWindow,
                canCopy: canCopy,
                copy: copy
            )
        }
    }

    final class WindowTrackingView: NSView {
        var windowDidChange: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            windowDidChange?(window)
        }
    }
}

struct PNGSmithDocumentCommands: Commands {
    @FocusedValue(\.pngsmithDocumentActions) private var actions

    var body: some Commands {
        CommandMenu("Image") {
            Button("Previous Image") {
                actions?.selectPrevious()
            }
            .keyboardShortcut("[", modifiers: [.command, .shift])
            .disabled(actions?.canCycle != true)

            Button("Next Image") {
                actions?.selectNext()
            }
            .keyboardShortcut("]", modifiers: [.command, .shift])
            .disabled(actions?.canCycle != true)

            Divider()

            Button("Close Image") {
                actions?.closeSelected()
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(actions?.canClose != true)
        }
    }
}
