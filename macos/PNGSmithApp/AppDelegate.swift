import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSUserInterfaceValidations {
    private let serviceProvider = PNGSmithServiceProvider()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = serviceProvider
        NSUpdateDynamicServices()
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        let urls = filenames.map(URL.init(fileURLWithPath:))
        OpenFileRouter.shared.enqueue(urls)
        sender.reply(toOpenOrPrint: .success)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        OpenFileRouter.shared.enqueue(urls)
    }

    @IBAction
    func copy(_ sender: Any?) {
        PNGSmithClipboardCommandRouter.shared.performCopy(in: NSApp.keyWindow)
    }

    func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(copy(_:)) {
            return PNGSmithClipboardCommandRouter.shared.canCopy(in: NSApp.keyWindow)
        }
        return true
    }
}
