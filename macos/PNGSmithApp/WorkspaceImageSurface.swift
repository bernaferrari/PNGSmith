import AppKit
import SwiftUI

enum WorkspaceMetrics {
    static let documentTabBarHeight: CGFloat = 42
    static let documentTabFilenameMaxWidth: CGFloat = 104
    static let documentTabStatusWidth: CGFloat = 38
    static let inspectorWidth: CGFloat = 330
}

enum WorkspaceSurface {
    static let chrome = Color(nsColor: .windowBackgroundColor)
    static let inspector = Color(nsColor: .windowBackgroundColor)
}

enum LoadingSpinnerContrast {
    case adaptive
    case light
}

struct LoadingSpinner: NSViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme

    var controlSize: ControlSize = .regular
    var contrast: LoadingSpinnerContrast = .adaptive

    func makeNSView(context: Context) -> NSProgressIndicator {
        let indicator = NSProgressIndicator()
        indicator.style = .spinning
        indicator.isIndeterminate = true
        indicator.isDisplayedWhenStopped = true
        indicator.controlSize = appKitControlSize
        indicator.appearance = resolvedAppearance
        indicator.startAnimation(nil)
        return indicator
    }

    func updateNSView(_ indicator: NSProgressIndicator, context: Context) {
        indicator.controlSize = appKitControlSize
        indicator.appearance = resolvedAppearance
        indicator.startAnimation(nil)
    }

    private var resolvedAppearance: NSAppearance? {
        let useDarkAppearance = contrast == .light || colorScheme == .dark
        return NSAppearance(named: useDarkAppearance ? .darkAqua : .aqua)
    }

    private var appKitControlSize: NSControl.ControlSize {
        if controlSize == .mini { return .mini }
        if controlSize == .small { return .small }
        if controlSize == .large { return .large }
        return .regular
    }
}

struct WorkspaceImageStage: View {
    var body: some View {
        Color(nsColor: .windowBackgroundColor)
            .overlay(Color.primary.opacity(0.035))
            .allowsHitTesting(false)
    }
}

private final class WorkspaceImageCache: @unchecked Sendable {
    static let shared = WorkspaceImageCache()

    private let images = NSCache<NSString, NSImage>()

    func image(at url: URL) -> NSImage? {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let revision = values?.contentModificationDate?.timeIntervalSinceReferenceDate ?? 0
        let byteCount = values?.fileSize ?? 0
        let key = "\(url.path)|\(revision)|\(byteCount)" as NSString
        if let cached = images.object(forKey: key) {
            return cached
        }
        guard let image = NSImage(contentsOf: url) else { return nil }
        images.setObject(image, forKey: key)
        return image
    }
}

struct WorkspaceFileImage: View {
    let url: URL
    let frame: CGRect

    private let image: NSImage?

    init(url: URL, frame: CGRect) {
        self.url = url
        self.frame = frame
        image = WorkspaceImageCache.shared.image(at: url)
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                LoadingSpinner()
            }
        }
        .frame(width: frame.width, height: frame.height)
        .clipped()
        .position(x: frame.midX, y: frame.midY)
    }
}

struct WorkspaceThumbnailImage: View {
    let url: URL

    private let image: NSImage?

    init(url: URL) {
        self.url = url
        image = WorkspaceImageCache.shared.image(at: url)
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
            } else {
                Color.primary.opacity(0.06)
            }
        }
    }
}

struct WorkspaceImageBackdrop: View {
    let frame: CGRect
    var viewScale: CGFloat = 1

    var body: some View {
        TransparencyCheckerboard()
            .frame(width: frame.width, height: frame.height)
            .clipped()
            .overlay {
                Rectangle()
                    .strokeBorder(
                        Color(nsColor: .separatorColor),
                        lineWidth: 1 / max(viewScale, 1)
                    )
            }
            .position(x: frame.midX, y: frame.midY)
            .allowsHitTesting(false)
    }
}
