import AppKit

final class PNGSmithServiceProvider: NSObject {
    @objc func compressPNG(
        _ pasteboard: NSPasteboard,
        userData profileName: String,
        error errorPointer: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        let urls = (pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] ?? [])
            .filter { $0.pathExtension.caseInsensitiveCompare("png") == .orderedSame }
        guard !urls.isEmpty else {
            errorPointer.pointee = "The selection contains no PNG files."
            return
        }
        do {
            var settings = PNGSmithSettingsStore.load()
            settings.apply(finderAction: profileName as String?)
            _ = try PNGSmithCore.execute(settings.request(inputs: urls))
        } catch {
            errorPointer.pointee = error.localizedDescription as NSString
        }
    }
}
