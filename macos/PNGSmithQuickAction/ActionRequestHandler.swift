import Foundation
import UniformTypeIdentifiers

final class ActionRequestHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        let contextBox = UncheckedSendableBox(context)
        Task {
            let context = contextBox.value
            do {
                let directory = try FileManager.default.url(
                    for: .itemReplacementDirectory,
                    in: .userDomainMask,
                    appropriateFor: FileManager.default.temporaryDirectory,
                    create: true
                )
                let inputs = try await FinderInputLoader.loadPNGs(from: context, into: directory)
                let action = Bundle.main.object(forInfoDictionaryKey: "PNGSmithActionProfile") as? String
                var settings = PNGSmithSettingsStore.load()
                settings.apply(finderAction: action)
                settings.createCopy = true
                settings.onlyIfSmaller = false
                let response = try PNGSmithCore.execute(settings.request(inputs: inputs))
                let outputItems = response.results.compactMap(\.output).map { path -> NSExtensionItem in
                    let url = URL(fileURLWithPath: path)
                    let provider = NSItemProvider()
                    provider.suggestedName = url.lastPathComponent
                    provider.registerFileRepresentation(
                        forTypeIdentifier: UTType.png.identifier,
                        fileOptions: [],
                        visibility: .all
                    ) { completion in
                        completion(url, false, nil)
                        return nil
                    }
                    let item = NSExtensionItem()
                    item.attachments = [provider]
                    return item
                }
                context.completeRequest(returningItems: outputItems)
            } catch {
                context.cancelRequest(withError: error)
            }
        }
    }
}

private final class UncheckedSendableBox<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}
