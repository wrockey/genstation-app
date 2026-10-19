import SwiftUI

// MARK: - Design Tokens
// Centralized design constants for GenStation.
// Values are derived from actual codebase usage patterns.

enum DS {

    // MARK: Corner Radii
    // Consolidated from 10 distinct values to 5.
    // All should use .continuous style for Apple squircle aesthetic.
    enum Radius {
        static let small: CGFloat = 6       // Small controls, tags, chips
        static let standard: CGFloat = 8    // Default — input fields, buttons, param controls
        static let card: CGFloat = 10       // Cards, grouped containers, configCard
        static let panel: CGFloat = 12      // Panels, large containers, popovers
        static let modal: CGFloat = 20      // Modals, sheets, full-screen overlays
    }

    // MARK: Spacing
    // Based on 4pt grid. Covers 95% of existing usage.
    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 6
        static let md: CGFloat = 8
        static let lg: CGFloat = 12
        static let xl: CGFloat = 16
        static let xxl: CGFloat = 20
        static let xxxl: CGFloat = 24
    }

    // MARK: Shadows
    // Three tiers matching existing usage patterns.
    enum Shadow {
        static let subtle = ShadowStyle(color: .black.opacity(0.08), radius: 2, x: 0, y: 1)
        static let standard = ShadowStyle(color: .black.opacity(0.10), radius: 6, x: 0, y: 2)
        static let prominent = ShadowStyle(color: .black.opacity(0.15), radius: 12, x: 0, y: 4)
    }

    // MARK: Animation
    // Standardized from 10+ spring variants and 8+ easing variants.
    enum Anim {
        // Springs — for interactive elements (buttons, expandables, drag)
        static let springFast = Animation.spring(response: 0.3, dampingFraction: 0.8)
        static let springDefault = Animation.spring(response: 0.4, dampingFraction: 0.75)
        static let springGentle = Animation.spring(response: 0.5, dampingFraction: 0.86)

        // Easing — for state changes (toggles, fades, panels)
        static let quick = Animation.easeInOut(duration: 0.2)
        static let standard = Animation.easeInOut(duration: 0.25)
        static let smooth = Animation.easeInOut(duration: 0.3)
    }

    // MARK: Materials
    // Documenting the existing two-tier strategy.
    // ultraThinMaterial: buttons, capsules, small overlays (69% of usage)
    // regularMaterial: sheet/popover backgrounds
    // ultraThickMaterial/thickMaterial: full-width nav bar backgrounds

    // MARK: Fonts
    // Shared font definitions extracted from ConfigurationSection + GeneralOptionsView.
    // Semantic text roles with sizes derived from codebase survey + readability goals.

    /// Medium-weight subheadline for form labels
    static let labelFont: Font = .system(.subheadline, design: .default, weight: .medium)

    /// Monospaced medium-weight for text fields displaying code/URLs/keys
    static func textFont(compact: Bool) -> Font {
        .system(size: compact ? 13 : 15, weight: .medium, design: .monospaced)
    }

    /// Standard font for picker labels
    static func pickerFont(compact: Bool) -> Font {
        .system(size: compact ? 13 : 15)
    }

    // MARK: Semantic Text Fonts
    // Standardized text sizes — bumped from original for readability.
    // Original → New: 8→10, 9→10, 10→11, 11→12, 12→13, 13→14, 14→15

    /// Smallest readable text: badges, version numbers, tiny metadata (was 8-9pt)
    static let tinyFont: Font = .system(size: 10)

    /// Secondary metadata, captions (was 10pt)
    static let captionFont: Font = .system(size: 11)

    /// Tertiary text, descriptions, tag labels (was 11pt)
    static let smallFont: Font = .system(size: 12)

    /// Standard body-adjacent text (was 12pt)
    static let footnoteFont: Font = .system(size: 13)

    /// Primary readable text (was 13pt)
    static let bodyFont: Font = .system(size: 14)

    /// Emphasized readable text (was 14pt)
    static let prominentFont: Font = .system(size: 15)
}

// MARK: - Shadow Style

struct ShadowStyle {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
}

// MARK: - View Extensions

extension View {
    /// Apply a standardized shadow from design tokens
    func shadow(_ style: ShadowStyle) -> some View {
        self.shadow(color: style.color, radius: style.radius, x: style.x, y: style.y)
    }

    /// Rounded rectangle clip with continuous (squircle) corners
    func continuousCornerRadius(_ radius: CGFloat) -> some View {
        self.clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}
