import SwiftUI

extension View {
    /// Banner titles on two lines sit closer together (iOS, tvOS and macOS 26+;
    /// earlier systems keep the normal spacing).
    /// `size` is the title's font size: the room left below grows with it, so
    /// letters like "д" never touch the facts row.
    @ViewBuilder func tightTitleLines(size: CGFloat) -> some View {
        if #available(iOS 26.0, tvOS 26.0, macOS 26.0, *) { lineHeight(.multiple(factor: 0.9)).padding(.bottom, size * 0.2) } else { self }
    }
}
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
