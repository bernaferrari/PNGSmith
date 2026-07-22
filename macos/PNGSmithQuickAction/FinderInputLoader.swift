import Foundation
import UniformTypeIdentifiers

enum FinderInputError: LocalizedError {
    case noPNGFiles
    var errorDescription: String? { "The Finder selection contains no PNG files." }
}

enum FinderInputLoader {
    static func loadPNGs(from context: NSExtensionContext, into directory: URL) async throws -> [URL] {
        var results: [URL] = []
        for item in context.inputItems.compactMap({ $0 as? NSExtensionItem }) {
            for provider in item.attachments ?? [] where provider.hasItemConformingToTypeIdentifier(UTType.png.identifier) {
                results.append(try await provider.copyPNGRepresentation(into: directory))
            }
        }
        guard !results.isEmpty else { throw FinderInputError.noPNGFiles }
        return results
    }
}

private extension NSItemProvider {
    /// Copies while the provider's completion handler is active. The source URL
    /// is temporary and is not guaranteed to survive after that handler returns.
    func copyPNGRepresentation(into directory: URL) async throws -> URL {
        let name = suggestedName.flatMap { $0.lowercased().hasSuffix(".png") ? $0 : $0 + ".png" }
            ?? UUID().uuidString + ".png"
        return try await withCheckedThrowingContinuation { continuation in
            _ = loadFileRepresentation(for: .png, openInPlace: false) { url, _, error in
                if let error { continuation.resume(throwing: error) }
                else if let url {
                    do {
                        let target = uniqueURL(in: directory, named: name)
                        try FileManager.default.copyItem(at: url, to: target)
                        continuation.resume(returning: target)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                } else { continuation.resume(throwing: FinderInputError.noPNGFiles) }
            }
        }
    }
}

private func uniqueURL(in directory: URL, named name: String) -> URL {
    let preferred = directory.appendingPathComponent(name)
    guard FileManager.default.fileExists(atPath: preferred.path) else { return preferred }
    return directory.appendingPathComponent(UUID().uuidString + "-" + name)
}
