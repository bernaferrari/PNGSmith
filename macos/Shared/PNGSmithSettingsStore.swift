import Foundation
import SwiftUI

@MainActor
final class PNGSmithSettingsStore: ObservableObject {
    nonisolated static var appGroup: String {
        Bundle.main.object(forInfoDictionaryKey: "PNGSmithAppGroup") as? String
            ?? "group.com.bernardoferrari.pngsmith"
    }
    nonisolated static let defaultsKey = "default-profile-v1"
    nonisolated static let reduceColorsKey = "dashboard-reduce-colors-v1"
    nonisolated static let maxColorsKey = "dashboard-max-colors-v1"
    nonisolated static let autoColorsKey = "dashboard-auto-colors-v1"
    nonisolated static let autoStrategyKey = "dashboard-auto-strategy-v1"
    nonisolated static let saveAsSelectedKey = "dashboard-save-as-selected-v1"

    @Published var settings: PNGSmithSettings { didSet { save() } }

    init() { settings = Self.load() }

    nonisolated static func load() -> PNGSmithSettings {
        let defaults = UserDefaults(suiteName: appGroup) ?? .standard
        guard let data = defaults.data(forKey: defaultsKey),
              var settings = try? JSONDecoder().decode(PNGSmithSettings.self, from: data)
        else { return PNGSmithSettings() }
        // The macOS app treats metadata preservation as part of its safety
        // promise, including for profiles saved by older versions.
        settings.metadata = "preserve"
        settings.onlyIfSmaller = true
        return settings
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        (UserDefaults(suiteName: Self.appGroup) ?? .standard).set(data, forKey: Self.defaultsKey)
    }

    func reset() {
        settings = PNGSmithSettings()
        let defaults = UserDefaults(suiteName: Self.appGroup) ?? .standard
        defaults.removeObject(forKey: Self.reduceColorsKey)
        defaults.removeObject(forKey: Self.maxColorsKey)
        defaults.removeObject(forKey: Self.autoColorsKey)
        defaults.removeObject(forKey: Self.autoStrategyKey)
        defaults.removeObject(forKey: Self.saveAsSelectedKey)
    }
}
