import SwiftUI
#if os(iOS)
import UIKit
#endif

/// A light tap for things the user presses. iPhone only, on by default, and the
/// "Haptic feedback" switch in Settings turns it off.
enum Haptics {
    static let key = "hapticFeedback"
    static func tap() {
        #if os(iOS)
        guard UIDevice.current.userInterfaceIdiom == .phone,
              UserDefaults.standard.object(forKey: key) as? Bool ?? true else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }
}

/// Wraps another button style and adds the tap before the action runs.
struct HapticButtonStyle<Base: PrimitiveButtonStyle>: PrimitiveButtonStyle {
    let base: Base
    func makeBody(configuration: Configuration) -> some View {
        Button(role: configuration.role) {
            Haptics.tap()
            configuration.trigger()
        } label: { configuration.label }
            .buttonStyle(base)
    }
}

extension View {
    func hapticButtonStyle<S: PrimitiveButtonStyle>(_ style: S) -> some View { buttonStyle(HapticButtonStyle(base: style)) }
}
