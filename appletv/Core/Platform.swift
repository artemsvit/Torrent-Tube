import SwiftUI
#if os(macOS)
import AppKit

/// The few UIKit types the shared code uses, under one name on every platform.
typealias PlatformImage = NSImage
typealias PlatformView = NSView

extension Image {
    init(platformImage: NSImage) { self.init(nsImage: platformImage) }
}

extension NSImage {
    convenience init(cgImage: CGImage) { self.init(cgImage: cgImage, size: .zero) }
    var cgImage: CGImage? { cgImage(forProposedRect: nil, context: nil, hints: nil) }
}
#else
import UIKit

typealias PlatformImage = UIImage
typealias PlatformView = UIView

extension Image {
    init(platformImage: UIImage) { self.init(uiImage: platformImage) }
}
#endif
