import AppKit
import SwiftUI

enum WorkspaceMetrics {
    static let documentTabBarHeight: CGFloat = 42
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
                ProgressView()
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
                        Color(nsColor: .separatorColor).opacity(0.75),
                        lineWidth: 1 / max(viewScale, 1)
                    )
            }
            .position(x: frame.midX, y: frame.midY)
            .allowsHitTesting(false)
    }
}
