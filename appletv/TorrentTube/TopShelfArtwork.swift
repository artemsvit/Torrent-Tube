import UIKit
import ImageIO
import os

/// Prepare lightweight cached banners in the app, outside the Top Shelf extension.
enum TopShelfArtwork {
    private static let log = Logger(subsystem: "com.artsvit.torrenttube.tv", category: "shelf-artwork")
    static func prepare(_ snapshot: ShelfSnapshot) async -> ShelfSnapshot {
        guard let directory = TopShelfStore.artworkDirectory else { return snapshot }
        let worker = Task.detached(priority: .utility) {
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            } catch {
                log.error("Cannot create shelf artwork directory: \(error.localizedDescription, privacy: .public)")
                return snapshot
            }
            var titles = Array(snapshot.titles.prefix(10))
            let previous = TopShelfStore.snapshot
            for index in titles.indices {
                if Task.isCancelled { return snapshot }
                guard let backdrop = titles[index].backdrop else { continue }
                // The kind and name are drawn on the image, so they are part of the key.
                let key = ShelfTitle.identifier("banner-v5|" + backdrop + "|" + (titles[index].kind ?? "") + "|" + titles[index].title)
                let file = directory.appendingPathComponent(key + ".jpg")
                if !FileManager.default.fileExists(atPath: file.path),
                   let url = URL(string: backdrop), ["https", "http"].contains(url.scheme),
                   let (data, response) = try? await URLSession.shared.data(for: URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 8)),
                   (response as? HTTPURLResponse)?.statusCode == 200,
                   let source = CGImageSourceCreateWithData(data as CFData, nil),
                   let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                     kCGImageSourceCreateThumbnailFromImageAlways: true,
                     kCGImageSourceCreateThumbnailWithTransform: true,
                     kCGImageSourceThumbnailMaxPixelSize: 1920
                   ] as CFDictionary) {
                    autoreleasepool {
                        do {
                            try render(banner: UIImage(cgImage: image), kind: titles[index].kind, title: titles[index].title).jpegData(compressionQuality: 0.92)?.write(to: file, options: .atomic)
                        } catch {
                            log.error("Cannot save shelf artwork: \(error.localizedDescription, privacy: .public)")
                        }
                    }
                }
                if FileManager.default.fileExists(atPath: file.path) {
                    titles[index].artworkID = key
                } else if previous?.server == snapshot.server,
                          let old = previous?.titles.first(where: { $0.id == titles[index].id && $0.backdrop == backdrop }),
                          TopShelfStore.artworkURL(for: old) != nil {
                    titles[index].artworkID = old.artworkID
                }
            }
            return ShelfSnapshot(server: snapshot.server, titles: titles)
        }
        return await withTaskCancellationHandler(operation: { await worker.value }, onCancel: { worker.cancel() })
    }

    /// tvOS shows the kind and name only while the trailer plays, so the
    /// still image carries them at the top left, where the trailer shows them.
    static func render(banner: UIImage, kind: String?, title: String) -> UIImage {
        let size = CGSize(width: 1920, height: 1080)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            let context = renderer.cgContext
            let scale = max(size.width / banner.size.width, size.height / banner.size.height)
            let width = banner.size.width * scale, height = banner.size.height * scale
            banner.draw(in: CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height))
            // A quiet lower fade keeps Apple's Dock and controls legible.
            let colors = [UIColor.clear.cgColor, UIColor.black.withAlphaComponent(0.12).cgColor,
                          UIColor.black.withAlphaComponent(0.55).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.65, 1]) {
                context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            }
            // A left shade under the kind, name, year and rating at the top left.
            let side = [UIColor.black.withAlphaComponent(0.6).cgColor, UIColor.clear.cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: side, locations: [0, 1]) {
                context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width * 0.6, y: 0), options: [])
            }
            let top = [UIColor.black.withAlphaComponent(0.45).cgColor, UIColor.clear.cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: top, locations: [0, 1]) {
                context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height * 0.4), options: [])
            }
            let shadow = NSShadow()
            shadow.shadowColor = UIColor.black.withAlphaComponent(0.6); shadow.shadowBlurRadius = 12; shadow.shadowOffset = CGSize(width: 0, height: 3)
            var y: CGFloat = 76
            if let kind, !kind.isEmpty {
                let label = NSAttributedString(string: kind.uppercased(), attributes: [
                    .font: UIFont.systemFont(ofSize: 22.5, weight: .bold), .kern: 2.25,
                    .foregroundColor: UIColor.white.withAlphaComponent(0.75), .shadow: shadow])
                label.draw(at: CGPoint(x: 90, y: y))
                y += 36
            }
            let name = titleText(title, shadow: shadow)
            let bounds = name.boundingRect(with: CGSize(width: 1150, height: CGFloat.greatestFiniteMagnitude),
                                           options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
            name.draw(with: CGRect(x: 90, y: y, width: 1150, height: ceil(bounds.height)),
                      options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        }
    }

    /// Wrap the complete name; reduce only unusually long titles to keep the artwork visible.
    static func titleText(_ title: String, shadow: NSShadow = NSShadow()) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        var fontSize: CGFloat = 54
        while true {
            let text = NSAttributedString(string: title, attributes: [
                .font: UIFont.systemFont(ofSize: fontSize, weight: .heavy), .foregroundColor: UIColor.white,
                .shadow: shadow, .paragraphStyle: paragraph])
            let height = text.boundingRect(with: CGSize(width: 1150, height: CGFloat.greatestFiniteMagnitude),
                                          options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).height
            if height <= 165 || fontSize <= 36 { return text }
            fontSize -= 3
        }
    }
}
