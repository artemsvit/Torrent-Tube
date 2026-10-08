import SwiftUI

/// The dark backdrop of the welcome screen on every device: near-black with a
/// soft blue glow from the top, like the light behind the hero images.
struct BrandBackground: View {
    var body: some View {
        ZStack {
            Color(red: 0.02, green: 0.03, blue: 0.05)
            RadialGradient(colors: [Color.torrentAccent.opacity(0.42), .clear],
                           center: UnitPoint(x: 0.5, y: -0.1), startRadius: 0, endRadius: 900)
            RadialGradient(colors: [Color(red: 0.45, green: 0.3, blue: 1).opacity(0.18), .clear],
                           center: UnitPoint(x: 1.05, y: 1.1), startRadius: 0, endRadius: 700)
        }
        .ignoresSafeArea()
    }
}

/// The app icon: a play mark on an accent gradient, with a glow.
struct BrandMark: View {
    var size: CGFloat
    var body: some View {
        Image(systemName: "play.fill")
            .font(.system(size: size * 0.46, weight: .bold))
            .foregroundStyle(.white)
            .offset(x: size * 0.03)
            .frame(width: size, height: size)
            .background(
                LinearGradient(colors: [Color(red: 0.36, green: 0.66, blue: 1), Color.torrentAccent, Color(red: 0.1, green: 0.38, blue: 0.95)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous).strokeBorder(.white.opacity(0.25), lineWidth: 1))
            .shadow(color: Color.torrentAccent.opacity(0.55), radius: size * 0.35, y: size * 0.08)
            .accessibilityHidden(true)
    }
}
