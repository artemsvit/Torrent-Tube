import AppKit

// Recreate the Torrent Tube's blue streaming mark as separate tvOS parallax layers.
let output = CommandLine.arguments[1]
let width = Int(CommandLine.arguments[2])!
let height = Int(CommandLine.arguments[3])!
let kind = CommandLine.arguments[4]
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                              samplesPerPixel: kind == "mobile" ? 3 : 4, hasAlpha: kind != "mobile", isPlanar: false, colorSpaceName: .deviceRGB,
                              bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
let rect = NSRect(x: 0, y: 0, width: width, height: height)
NSColor.clear.setFill()
rect.fill()
if kind == "shelf" {
    // A restrained cinema banner, rendered at each asset's native size.
    NSGradient(starting: NSColor(srgbRed: 0.018, green: 0.025, blue: 0.05, alpha: 1),
               ending: NSColor(srgbRed: 0.035, green: 0.09, blue: 0.15, alpha: 1))!.draw(in: rect, angle: 15)
    let h = CGFloat(height)
    let w = CGFloat(width)
    for index in 0..<5 {
        let arc = NSBezierPath(ovalIn: NSRect(x: w * 0.48 + CGFloat(index) * h * 0.2, y: -h * 0.9,
                                            width: h * 2.1, height: h * 2.1))
        NSColor(srgbRed: 0.3, green: 0.6, blue: 0.9, alpha: 0.035).setStroke()
        arc.lineWidth = h * 0.055
        arc.stroke()
    }
    let title = "Torrent Tube" as NSString
    let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: h * 0.112, weight: .semibold), .foregroundColor: NSColor.white]
    let size = title.size(withAttributes: attributes)
    let mark = h * 0.085
    let gap = h * 0.07
    let left = (w - size.width - mark - gap) / 2
    let triangle = NSBezierPath()
    triangle.move(to: NSPoint(x: left, y: h * 0.5 - mark * 0.65))
    triangle.line(to: NSPoint(x: left + mark, y: h * 0.5))
    triangle.line(to: NSPoint(x: left, y: h * 0.5 + mark * 0.65))
    triangle.close()
    NSColor(srgbRed: 0.3, green: 0.65, blue: 1, alpha: 1).setFill()
    triangle.fill()
    title.draw(at: NSPoint(x: left + mark + gap, y: (h - size.height) / 2), withAttributes: attributes)
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
    exit(0)
}
if kind != "foreground" {
    NSGradient(starting: NSColor(srgbRed: 0.169, green: 0.541, blue: 1, alpha: 1),
               ending: NSColor(srgbRed: 0.024, green: 0.408, blue: 0.882, alpha: 1))!.draw(in: rect, angle: -45)
}
if kind != "background" {
    let scale = CGFloat(height) * 0.76 / 64
    let centerX = kind == "shelf" ? CGFloat(width) * 0.29 : CGFloat(width) / 2
    func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
        NSPoint(x: centerX + (x - 32) * scale, y: CGFloat(height) / 2 - (y - 32) * scale)
    }
    let path = NSBezierPath()
    path.move(to: point(24, 14))
    path.line(to: point(48, 32))
    path.line(to: point(24, 50))
    path.close()
    NSColor.white.setFill()
    path.fill()
    if kind == "shelf" {
        let text = "Torrent Tube" as NSString
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: CGFloat(height) * 0.15, weight: .bold), .foregroundColor: NSColor.white]
        let size = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: CGFloat(width) * 0.43, y: (CGFloat(height) - size.height) / 2), withAttributes: attributes)
    }
}
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
