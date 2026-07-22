import AppIntents

struct PNGSmithAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CompressPNGIntent(),
            phrases: [
                "Compress PNG with \(.applicationName)",
                "Minify PNG with \(.applicationName)"
            ],
            shortTitle: "Compress PNG",
            systemImageName: "photo.badge.arrow.down"
        )
    }
}

