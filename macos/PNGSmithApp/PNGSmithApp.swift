import SwiftUI

@main
struct PNGSmithApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var settings = PNGSmithSettingsStore()
    @StateObject private var updates = UpdateController()
    @StateObject private var openFiles = OpenFileRouter.shared

    var body: some Scene {
        WindowGroup {
            CompressionDashboard()
                .environmentObject(settings)
                .environmentObject(openFiles)
        }
        .defaultSize(width: 1080, height: 740)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesCommand(updates: updates)
            }
            PNGSmithDocumentCommands()
        }

        Settings {
            SettingsView().environmentObject(settings)
        }
    }
}
