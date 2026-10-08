import SwiftUI
import ImageIO

/// Reuse a few decoded banners; compressed URLCache responses alone still need decoding.
actor HeroArtworkCache {
    static let shared: HeroArtworkCache = {
        let store = HeroArtworkCache()
        #if !os(macOS)
        NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification,
                                               object: nil, queue: nil) { _ in
            Task { await store.clear() }
        }
        #endif
        return store
    }()
    private static let decodeQueue = DispatchQueue(label: "TorrentTube.hero-decode", qos: .userInitiated)
    private let images = NSCache<NSURL, PlatformImage>()
    private var loading: [URL: Task<PlatformImage?, Error>] = [:]
    private var generation = 0
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
        images.countLimit = 3
        images.totalCostLimit = 24 * 1024 * 1024
    }

    func clear() {
        generation += 1
        images.removeAllObjects()
    }

    func image(for url: URL) async throws -> PlatformImage? {
        if let image = images.object(forKey: url as NSURL) { return image }
        if let pending = loading[url] { return try await pending.value }
        let epoch = generation
        let session = session
        let pending = Task<PlatformImage?, Error> {
            let (data, response) = try await session.data(for: URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad))
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { return nil }
            return await withCheckedContinuation { continuation in
                Self.decodeQueue.async { continuation.resume(returning: HeroBackdrop.decode(data)) }
            }
        }
        loading[url] = pending
        defer { loading[url] = nil }
        let image = try await pending.value
        if epoch == generation, let image, let cgImage = image.cgImage {
            images.setObject(image, forKey: url as NSURL, cost: cgImage.bytesPerRow * cgImage.height)
        }
        return image
    }
}

/// Keep both images at a fixed size and blend their opacity after decoding.
struct HeroBackdrop: View {
    let url: URL?
    var nextURL: URL? = nil
    var alignment: Alignment = .center
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var current: PlatformImage?
    @State private var outgoing: PlatformImage?
    @State private var blend: Double = 1

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.clear
                if let outgoing { artwork(outgoing, size: geometry.size) }
                if let current { artwork(current, size: geometry.size).opacity(blend) }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .accessibilityHidden(true)
        .task(id: url) { await load() }
        .task(id: nextURL) {
            if let nextURL { _ = try? await HeroArtworkCache.shared.image(for: nextURL) }
        }
    }

    private func artwork(_ image: PlatformImage, size: CGSize) -> some View {
        Image(platformImage: image).resizable().scaledToFill()
            .frame(width: size.width, height: size.height, alignment: alignment)
            .clipped()
            .id(ObjectIdentifier(image))
            .transition(.identity)
            .transaction { $0.animation = nil }
    }

    private func load() async {
        guard let url else { reset(); return }
        do {
            let decoded = try await HeroArtworkCache.shared.image(for: url)
            try Task.checkCancellation()
            guard let decoded else { reset(); return }
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                outgoing = current
                current = decoded
                blend = outgoing == nil || reduceMotion ? 1 : 0
            }
            if outgoing != nil, !reduceMotion {
                withAnimation(.easeInOut(duration: 0.45)) { blend = 1 }
                try await Task.sleep(for: .milliseconds(450))
            }
            outgoing = nil
        } catch is CancellationError {} catch {
            if !Task.isCancelled { reset() }
        }
    }

    private func reset() {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) { current = nil; outgoing = nil; blend = 1 }
    }

    nonisolated static func decode(_ data: Data) -> PlatformImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1920,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        return PlatformImage(cgImage: image)
    }
}

/// The dark backdrop of the welcome screen on every device: near-black with a
/// soft blue glow from the top, like the light behind the hero images.
extension Color {
    /// The near-black every page sits on; hero images fade into it.
    static let appBase = Color(red: 0.02, green: 0.03, blue: 0.05)
}

/// Behind every page: the welcome screen's glow, quieter, so it never
/// competes with posters. Sized to the screen, so a phone gets the same look.
struct AppBackground: View {
    var body: some View {
        GeometryReader { geometry in
            let reach = max(geometry.size.width, geometry.size.height)
            ZStack {
                Color.appBase
                RadialGradient(colors: [Color.torrentAccent.opacity(0.22), .clear],
                               center: UnitPoint(x: 0.5, y: -0.15), startRadius: 0, endRadius: reach * 0.75)
                RadialGradient(colors: [Color(red: 0.45, green: 0.3, blue: 1).opacity(0.10), .clear],
                               center: UnitPoint(x: 1.05, y: 1.05), startRadius: 0, endRadius: reach * 0.6)
            }
        }
        .ignoresSafeArea()
    }
}

struct BrandBackground: View {
    var body: some View {
        ZStack {
            Color.appBase
            RadialGradient(colors: [Color.torrentAccent.opacity(0.42), .clear],
                           center: UnitPoint(x: 0.5, y: -0.1), startRadius: 0, endRadius: 900)
            RadialGradient(colors: [Color(red: 0.45, green: 0.3, blue: 1).opacity(0.18), .clear],
                           center: UnitPoint(x: 1.05, y: 1.1), startRadius: 0, endRadius: 700)
        }
        .ignoresSafeArea()
    }
}

/// While the app connects to the saved server at launch: the brand mark
/// breathing on the welcome screen's glow, a ripple, and "Connecting…".
/// The connection screen appears only when connecting fails.
struct SplashView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathe = false
    @State private var ripple = false
    #if os(tvOS)
    private let mark: CGFloat = 170, title: CGFloat = 76, caption: CGFloat = 28
    #else
    private let mark: CGFloat = 104, title: CGFloat = 36, caption: CGFloat = 16
    #endif
    var body: some View {
        ZStack {
            BrandBackground()
            Circle().fill(Color.torrentAccent.opacity(0.22))
                .frame(width: mark * 3.2, height: mark * 3.2).blur(radius: mark * 0.6)
                .scaleEffect(breathe ? 1.15 : 0.85)
            VStack(spacing: mark * 0.32) {
                ZStack {
                    ForEach(0..<2) { ring in
                        RoundedRectangle(cornerRadius: mark * 0.3, style: .continuous)
                            .strokeBorder(Color.torrentAccent.opacity(0.5), lineWidth: 2)
                            .frame(width: mark, height: mark)
                            .scaleEffect(ripple ? 1.7 : 1)
                            .opacity(ripple ? 0 : 0.8)
                            .animation(reduceMotion ? nil : .easeOut(duration: 2.2).repeatForever(autoreverses: false).delay(Double(ring) * 1.1), value: ripple)
                    }
                    BrandMark(size: mark).scaleEffect(breathe ? 1.04 : 0.98)
                }
                Text("Torrent Tube").font(.system(size: title, weight: .heavy)).foregroundStyle(.white)
                HStack(spacing: 10) {
                    ProgressView().tint(.white.opacity(0.7))
                    Text(L("Connecting…"))
                        .font(.system(size: caption, weight: .medium)).foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { breathe = true }
            ripple = true
        }
        .accessibilityElement(children: .combine)
    }
}

/// A failed connection on the connection screen: an icon, what happened and
/// what to check, in a tinted panel.
struct ConnectionProblemView: View {
    let title: String
    let tip: String?
    var settings: (() -> Void)? = nil
    #if os(tvOS)
    private let icon: CGFloat = 30, titleSize: CGFloat = 28, tipSize: CGFloat = 24, pad: CGFloat = 26
    #else
    private let icon: CGFloat = 17, titleSize: CGFloat = 16, tipSize: CGFloat = 14, pad: CGFloat = 14
    #endif
    var body: some View {
        HStack(alignment: .top, spacing: pad * 0.8) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: icon, weight: .semibold)).foregroundStyle(Color(red: 1, green: 0.62, blue: 0.3))
                .frame(width: icon * 2.1, height: icon * 2.1)
                .background(Color(red: 1, green: 0.55, blue: 0.2).opacity(0.16), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: titleSize, weight: .semibold)).foregroundStyle(.white)
                if let tip { Text(tip).font(.system(size: tipSize)).foregroundStyle(.white.opacity(0.65)) }
                if let settings {
                    Button(L("Open device settings"), action: settings)
                        .font(.system(size: tipSize, weight: .semibold)).foregroundStyle(Color.torrentAccent)
                        .buttonStyle(.plain).padding(.top, 4)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(pad)
        .background(Color(red: 1, green: 0.5, blue: 0.2).opacity(0.08), in: RoundedRectangle(cornerRadius: pad * 1.2, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: pad * 1.2, style: .continuous).strokeBorder(Color(red: 1, green: 0.55, blue: 0.25).opacity(0.25)))
        .accessibilityElement(children: .combine)
    }
}

/// Rounded play triangle outline matching the app brand icon.
struct RoundedPlayShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        guard w > 0, h > 0 else { return path }
        
        let strokeWidth = w * (10.4 / 91.0)
        let halfStroke = strokeWidth / 2.0
        let rL = w * (10.0 / 91.0)
        let rR = w * (10.5 / 91.0)
        
        let cL_x = rect.minX + halfStroke + rL
        let cTop_y = rect.minY + halfStroke + rL
        let cBot_y = rect.maxY - (halfStroke + rL)
        let cR_x = rect.maxX - (halfStroke + rR)
        let cR_y = rect.midY
        
        let cTop = CGPoint(x: cL_x, y: cTop_y)
        let cBot = CGPoint(x: cL_x, y: cBot_y)
        let cRight = CGPoint(x: cR_x, y: cR_y)
        
        let dx_top = cRight.x - cTop.x
        let dy_top = cRight.y - cTop.y
        let dist_top = hypot(dx_top, dy_top)
        guard dist_top > abs(rL - rR) else { return path }
        let angle_top = atan2(dy_top, dx_top)
        
        let alpha_top = asin((rL - rR) / dist_top)
        let norm_angle_top = angle_top - .pi / 2.0 + alpha_top
        
        let tTop_1 = CGPoint(x: cTop.x + rL * cos(norm_angle_top), y: cTop.y + rL * sin(norm_angle_top))
        let tRight_1 = CGPoint(x: cRight.x + rR * cos(norm_angle_top), y: cRight.y + rR * sin(norm_angle_top))
        let tBot_1 = CGPoint(x: tTop_1.x, y: rect.maxY - (tTop_1.y - rect.minY))
        
        path.move(to: CGPoint(x: rect.minX + halfStroke, y: cBot.y))
        path.addLine(to: CGPoint(x: rect.minX + halfStroke, y: cTop.y))
        path.addArc(center: cTop, radius: rL, startAngle: .radians(.pi), endAngle: .radians(norm_angle_top), clockwise: false)
        path.addLine(to: tRight_1)
        let norm_angle_bot = -norm_angle_top
        path.addArc(center: cRight, radius: rR, startAngle: .radians(norm_angle_top), endAngle: .radians(norm_angle_bot), clockwise: false)
        path.addLine(to: tBot_1)
        path.addArc(center: cBot, radius: rL, startAngle: .radians(norm_angle_bot), endAngle: .radians(.pi), clockwise: false)
        path.closeSubpath()
        return path
    }
}

/// The app icon: a rounded play outline on an accent gradient, with a glow.
struct BrandMark: View {
    var size: CGFloat
    var body: some View {
        let iconH = size * (102.0 / 180.0)
        let iconW = iconH * (91.0 / 102.0)
        let strokeW = iconW * (10.4 / 91.0)
        
        RoundedPlayShape()
            .stroke(style: StrokeStyle(lineWidth: strokeW, lineCap: .round, lineJoin: .round))
            .foregroundStyle(.white)
            .frame(width: iconW, height: iconH)
            .offset(x: size * 0.027)
            .frame(width: size, height: size)
            .background(
                LinearGradient(colors: [Color(red: 0.11, green: 0.48, blue: 0.95), Color.torrentAccent, Color(red: 0.05, green: 0.39, blue: 0.84)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous).strokeBorder(.white.opacity(0.25), lineWidth: 1))
            .shadow(color: Color.torrentAccent.opacity(0.55), radius: size * 0.35, y: size * 0.08)
            .accessibilityHidden(true)
    }
}

#if !os(tvOS)
enum HeroLayout {
    /// The banner on Home and on a title page - the same height on both, so
    /// opening a title never makes it jump.
    static func bannerHeight(screenHeight: CGFloat, sizeClass: UserInterfaceSizeClass?) -> CGFloat {
        let base = mobileHeight(screenHeight: screenHeight, sizeClass: sizeClass)
        return screenHeight >= 500 ? max(base, screenHeight * (sizeClass == .regular ? 0.82 : 0.88)) : base
    }
    /// Adaptive height for the hero banner on mobile (iPhone / iPad).
    static func mobileHeight(screenHeight: CGFloat, sizeClass: UserInterfaceSizeClass?) -> CGFloat {
        if sizeClass == .regular {
            return min(max(screenHeight * 0.88, 640), 1040)
        }
        if screenHeight < 500 {
            return max(screenHeight * 0.88, 340)
        }
        return min(max(screenHeight * 0.70, 500), 650)
    }
}
#endif
