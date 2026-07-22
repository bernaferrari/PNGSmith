import Combine
import Foundation
import Sparkle
import SwiftUI

@MainActor
final class UpdateController: ObservableObject {
    @Published private(set) var canCheckForUpdates = false

    private let updaterController: SPUStandardUpdaterController
    private var canCheckSubscription: AnyCancellable?

    init(bundle: Bundle = .main) {
        let feed = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String
        let publicKey = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
        let isConfigured = Self.hasValidConfiguration(feed: feed, publicKey: publicKey)

        updaterController = SPUStandardUpdaterController(
            startingUpdater: isConfigured,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        guard isConfigured else { return }
        canCheckSubscription = updaterController.updater
            .publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .assign(to: \.canCheckForUpdates, on: self)
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    private static func hasValidConfiguration(feed: String?, publicKey: String?) -> Bool {
        guard let feed,
              let url = URL(string: feed),
              url.scheme == "https",
              url.host != nil,
              let publicKey,
              Data(base64Encoded: publicKey)?.count == 32
        else { return false }
        return true
    }
}

struct CheckForUpdatesCommand: View {
    @ObservedObject var updates: UpdateController

    var body: some View {
        Button("Check for Updates…") {
            updates.checkForUpdates()
        }
        .disabled(!updates.canCheckForUpdates)
    }
}
