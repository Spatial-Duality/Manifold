import SwiftUI

/// Consistent spacing scale used across all views.
/// Base-4 scale inspired by Things 3 and Raycast.
enum Spacing {
    /// 4pt — tight inline spacing (icon-to-text gaps)
    static let tight: CGFloat = 4
    /// 8pt — standard list row internal padding
    static let standard: CGFloat = 8
    /// 12pt — section spacing within a view
    static let section: CGFloat = 12
    /// 16pt — standard view edge padding
    static let edge: CGFloat = 16
    /// 24pt — section separation, onboarding elements
    static let large: CGFloat = 24
    /// 32pt — large separation between major sections
    static let xlarge: CGFloat = 32

    // MARK: - Corner Radii

    /// 6pt — inline pills, command row hover, small interactive elements
    static let cornerSmall: CGFloat = 6
    /// 10pt — cards, stat containers, medium interactive surfaces
    static let cornerMedium: CGFloat = 10
    /// 12pt — section cards, session cards, overlays
    static let cornerLarge: CGFloat = 12
}

// MARK: - Glass Helpers

/// View modifier that applies `.glassEffect` on macOS 26+ with `.ultraThinMaterial` fallback.
struct GlassBackground<S: Shape>: ViewModifier {
    let shape: S
    let tint: Color?

    init(in shape: S, tint: Color? = nil) {
        self.shape = shape
        self.tint = tint
    }

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            if let tint {
                content.glassEffect(.regular.tint(tint), in: shape)
            } else {
                content.glassEffect(.regular, in: shape)
            }
        } else {
            content.background(.ultraThinMaterial, in: shape)
        }
    }
}

extension View {
    /// Apply Liquid Glass on macOS 26+, `.ultraThinMaterial` on older.
    /// Use ONLY on navigation chrome (overlays, command palette, error banners).
    /// Content views should use `.contentCard()` instead.
    func glassBackground(
        in shape: some Shape = RoundedRectangle(cornerRadius: Spacing.cornerLarge),
        tint: Color? = nil
    ) -> some View {
        modifier(GlassBackground(in: shape, tint: tint))
    }

    /// Subtle card background for content-area cards. NOT glass.
    /// Per DESIGN.md: "Glass is the navigation layer. Content never uses glass."
    @ViewBuilder
    func contentCard(tint: Color? = nil) -> some View {
        if let tint {
            self.background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: Spacing.cornerLarge))
        } else {
            self.background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: Spacing.cornerLarge))
        }
    }

    /// Apply `.glassProminent` on macOS 26+, `.borderedProminent` on older.
    @ViewBuilder
    func glassProminentButton() -> some View {
        if #available(macOS 26, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent)
        }
    }

    /// Apply `.glass` on macOS 26+, `.bordered` on older.
    @ViewBuilder
    func glassButton() -> some View {
        if #available(macOS 26, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
    }
}

