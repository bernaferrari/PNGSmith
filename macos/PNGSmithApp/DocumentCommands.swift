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
