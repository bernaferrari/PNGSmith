import Combine
import Foundation

@MainActor
final class OpenFileRouter: ObservableObject {
    static let shared = OpenFileRouter()

    @Published private(set) var revision = 0
    private var pendingURLs: [URL] = []

    func enqueue(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        for url in urls where !pendingURLs.contains(url) {
            pendingURLs.append(url)
        }
        revision += 1
    }

    func takePendingURLs() -> [URL] {
        defer { pendingURLs.removeAll() }
        return pendingURLs
    }
}
