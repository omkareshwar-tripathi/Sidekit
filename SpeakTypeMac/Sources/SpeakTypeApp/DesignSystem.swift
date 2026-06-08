import SwiftUI

/// The single source of truth for SpeakType's look — glass material, colors, type, spacing,
/// radii (spec §6). Every view references these tokens; no per-view hardcoded colors or metrics.
enum DS {
    enum Palette {
        static let accent    = Color(red: 0.43, green: 0.37, blue: 0.99) // #6D5EFC
        static let accentAlt = Color(red: 0.77, green: 0.30, blue: 0.75) // #C44BFF
        static let recDot    = Color(red: 0.93, green: 0.27, blue: 0.27) // recording dot (red)
        static let success   = Color(red: 0.30, green: 0.78, blue: 0.46) // success (green)
        static let glassTint = Color.black.opacity(0.55)                 // dark wash over the blur
        static let hairline  = Color.white.opacity(0.12)                 // hairline borders
        static let textPrimary   = Color.white.opacity(0.95)
        static let textSecondary = Color.white.opacity(0.60)
    }

    /// Brand sweep for active/recording affordances (the pill's accent gradient).
    static let accentGradient = LinearGradient(
        colors: [Palette.accent, Palette.accentAlt],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    enum Space {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 14
        static let lg: CGFloat = 22
    }

    enum Radius {
        static let pill: CGFloat = 999 // full-round
        static let card: CGFloat = 14
    }

    enum Typography {
        static let title   = Font.system(size: 17, weight: .semibold, design: .rounded)
        static let body    = Font.system(size: 13, weight: .regular,  design: .rounded)
        static let caption = Font.system(size: 11, weight: .medium,   design: .rounded)
    }
}

/// Dark frosted-glass surface (spec §6): a dark tint washed over `.ultraThinMaterial`, finished
/// with a hairline border and a soft drop shadow. Back-to-front the layers are: blurred desktop
/// → material → dark tint → content, so the content stays crisp while the panel reads as glass.
struct GlassCard: ViewModifier {
    var cornerRadius: CGFloat = DS.Radius.card

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return content
            .background(DS.Palette.glassTint, in: shape)
            .background(.ultraThinMaterial, in: shape)
            .overlay(shape.strokeBorder(DS.Palette.hairline, lineWidth: 1))
            .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
    }
}

extension View {
    /// Applies the standard dark-glass surface (spec §6 material).
    func glassCard(cornerRadius: CGFloat = DS.Radius.card) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius))
    }
}

/// The SpeakType brand mark — the 5-bar equalizer from the app icon, in the accent gradient.
/// Used wherever the window wants to echo the icon (e.g. empty states).
struct EqualizerMark: View {
    var height: CGFloat = 56
    // Bar heights echo the app icon's equalizer (make-icon.swift's [0.32,0.60,0.92,…] normalized).
    private let shape: [CGFloat] = [0.35, 0.65, 1.0, 0.65, 0.35]

    var body: some View {
        HStack(spacing: height * 0.09) {
            ForEach(shape.indices, id: \.self) { i in
                Capsule()
                    .fill(DS.accentGradient)
                    .frame(width: height * 0.16, height: height * shape[i])
            }
        }
        .frame(height: height)
    }
}
