import SwiftUI

enum ClaudeTheme {
    static let accent = Color(red: 0.80, green: 0.40, blue: 0.27)
    static let textPrimary = Color.primary
    static let textSecondary = Color.secondary
    static let cornerRadius: CGFloat = 18
    static let cardCornerRadius: CGFloat = 14
}

// MARK: - Panels

/// Applies Apple's real Liquid Glass material on macOS 26+ (per
/// developer.apple.com/documentation/swiftui/view/glasseffect(_:in:)),
/// and falls back to a Material-based approximation on older systems.
struct GlassPanel: ViewModifier {
    var cornerRadius: CGFloat = ClaudeTheme.cardCornerRadius
    var tint: Color = .clear

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(
                    tint == .clear ? .regular : .regular.tint(tint.opacity(0.35)),
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
        } else {
            content
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(.regularMaterial)
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(tint.opacity(0.12))
                    }
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.5), Color.white.opacity(0.05), ClaudeTheme.accent.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
}

extension View {
    func glassPanel(cornerRadius: CGFloat = ClaudeTheme.cardCornerRadius, tint: Color = .clear) -> some View {
        modifier(GlassPanel(cornerRadius: cornerRadius, tint: tint))
    }

    /// Wraps content in a `GlassEffectContainer` on macOS 26+ so multiple
    /// glass panels render together and can morph, per Apple's guidance to
    /// always group Liquid Glass elements in a container. No-op fallback
    /// below macOS 26.
    @ViewBuilder
    func claudeGlassContainer(spacing: CGFloat = 16) -> some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                self
            }
        } else {
            self
        }
    }
}

// MARK: - Buttons

/// Fallback primary button style for macOS < 26: a hand-styled glass capsule.
/// On macOS 26+, use `.claudePrimaryButton()` instead, which applies Apple's
/// real `.glassProminent` button style directly (built-in styles like
/// `.glass`/`.glassProminent` can only be applied to an actual `Button`, not
/// composed from inside another custom `ButtonStyle`).
struct ClaudeButtonStyle: ButtonStyle {
    var prominent: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .background(.thinMaterial, in: Capsule(style: .continuous))
            .background(
                Capsule(style: .continuous)
                    .fill(ClaudeTheme.accent.opacity(configuration.isPressed ? 0.72 : (prominent ? 0.92 : 0.55)))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color.white.opacity(0.35), lineWidth: 0.75)
            )
            .foregroundColor(.white)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Fallback secondary/tertiary button style for macOS < 26 (Settings, Quit,
/// Cancel-style actions). On macOS 26+, use `.claudeGhostButton()` instead.
struct ClaudeGhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(ClaudeTheme.textSecondary)
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

extension View {
    /// Primary call-to-action button styling. Applies Apple's real
    /// `.glassProminent` glass button style on macOS 26+ (per
    /// developer.apple.com/documentation/swiftui/glassbuttonstyle), falling
    /// back to a hand-styled glass capsule on older systems.
    @ViewBuilder
    func claudePrimaryButton() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glassProminent)
                .tint(ClaudeTheme.accent)
        } else {
            self.buttonStyle(ClaudeButtonStyle())
        }
    }

    /// Secondary/tertiary button styling (Settings, Quit, Cancel). Applies
    /// Apple's real `.glass` button style on macOS 26+, falling back to a
    /// plain text-style ghost button on older systems.
    @ViewBuilder
    func claudeGhostButton() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(ClaudeGhostButtonStyle())
        }
    }
}
