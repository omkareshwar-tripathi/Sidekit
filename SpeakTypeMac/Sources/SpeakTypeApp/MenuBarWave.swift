import AppKit

/// Renders the menu-bar equalizer as a live waveform while recording. Same 5-bar mark as the
/// static icon (`MenuBarIcon.pdf`), but each bar's height is driven by the mic `level` with a
/// per-bar `phase` wobble so the bars "dance" instead of scaling as one block. Returns a template
/// `NSImage` (macOS tints it for light/dark menu bars).
enum MenuBarWave {
    private static let pt: CGFloat = 20        // rendered point size (matches the static glyph)
    private static let scale: CGFloat = 3      // supersample for crisp menu-bar downscale
    private static let base: [CGFloat] = [0.55, 0.80, 1.0, 0.80, 0.55]  // resting silhouette

    /// `level` is the 0…1 mic loudness; `phase` advances each frame to animate the wobble.
    static func icon(level: CGFloat, phase: Double) -> NSImage {
        let px = Int(pt * scale)
        let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))

        let w = CGFloat(px)
        let barW = 0.12 * w, gap = 0.07 * w
        let total = 5 * barW + 4 * gap
        var x = (w - total) / 2
        let cy = w / 2
        let amp = 0.30 + 0.70 * min(1, max(0, level))
        for i in 0..<5 {
            let wobble = 0.5 + 0.5 * sin(phase + Double(i) * 0.9)
            let hf = min(1.0, max(0.18, base[i] * (0.30 + amp * CGFloat(wobble))))
            let h = hf * w * 0.94
            ctx.addPath(CGPath(roundedRect: CGRect(x: x, y: cy - h / 2, width: barW, height: h),
                               cornerWidth: barW / 2, cornerHeight: barW / 2, transform: nil))
            ctx.fillPath()
            x += barW + gap
        }

        let image = NSImage(cgImage: ctx.makeImage()!, size: NSSize(width: pt, height: pt))
        image.isTemplate = true
        return image
    }
}
