#!/usr/bin/env swift
// Generates SpeakType's app icon from code — no external art, fully reproducible.
//
// The mark is the SpeakType **equalizer** (the same 5-bar waveform shipped in the Windows app —
// see windows/SpeakType.App/Branding/AppIcon.cs), drawn once in a 0…1000 design space and
// rendered two ways:
//   • the full-colour app icon  → AppBundle/AppIcon.iconset/*.png → (iconutil) AppIcon.icns
//   • a monochrome menu-bar glyph → AppBundle/MenuBarIcon.pdf (a template image macOS tints)
//
// Run from SpeakTypeMac/:  ./Scripts/make-icon.swift   (then build-app.sh copies them in)
// Re-run only when the artwork changes; the outputs are committed.

import AppKit
import CoreGraphics

// MARK: - Brand (mirrors DS.Palette in DesignSystem.swift)

let accent    = CGColor(red: 0.43, green: 0.37, blue: 0.99, alpha: 1) // #6D5EFC
let accentAlt = CGColor(red: 0.77, green: 0.30, blue: 0.75, alpha: 1) // #C44BFF
let cs = CGColorSpace(name: CGColorSpace.sRGB)!

// MARK: - The mark

/// Draws the SpeakType equalizer — 5 symmetric rounded bars — filled with the current colour,
/// in a 0…1000 (y-up) design space centred on x=500. `refW` scales the whole mark: bar width,
/// gap and heights are all fractions of it (proportions hand-matched to the Windows `.ico`).
func drawEqualizer(_ ctx: CGContext, refW: CGFloat, cy: CGFloat = 500) {
    let heights: [CGFloat] = [0.32, 0.60, 0.92, 0.60, 0.32]   // full bar heights ÷ refW
    let barW = 0.12 * refW, gap = 0.07 * refW
    let total = CGFloat(heights.count) * barW + CGFloat(heights.count - 1) * gap
    var x = 500 - total / 2
    for hf in heights {
        let h = hf * refW
        ctx.addPath(CGPath(roundedRect: CGRect(x: x, y: cy - h / 2, width: barW, height: h),
                           cornerWidth: barW / 2, cornerHeight: barW / 2, transform: nil))
        ctx.fillPath()
        x += barW + gap
    }
}

/// Maps the 0…1000 design space onto `size`×`size` and runs `body`.
func inDesignSpace(_ ctx: CGContext, size: Int, _ body: () -> Void) {
    let s = CGFloat(size) / 1000
    ctx.saveGState(); ctx.scaleBy(x: s, y: s); body(); ctx.restoreGState()
}

/// Renders the full colour app icon (gradient squircle + white equalizer) at `size`×`size`.
func renderAppIcon(size: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                        bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    inDesignSpace(ctx, size: size) {
        // Rounded-rect "squircle" tile with a margin for the macOS drop-shadow gutter.
        let tile = CGRect(x: 80, y: 80, width: 840, height: 840)
        let tilePath = CGPath(roundedRect: tile, cornerWidth: 190, cornerHeight: 190, transform: nil)
        ctx.saveGState()
        ctx.addPath(tilePath); ctx.clip()
        let grad = CGGradient(colorsSpace: cs, colors: [accent, accentAlt] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(grad, start: CGPoint(x: 80, y: 920), end: CGPoint(x: 920, y: 80), options: [])
        // Soft top-left sheen for a little depth.
        let sheen = CGGradient(colorsSpace: cs,
                               colors: [CGColor(gray: 1, alpha: 0.20), CGColor(gray: 1, alpha: 0)] as CFArray,
                               locations: [0, 1])!
        ctx.drawRadialGradient(sheen, startCenter: CGPoint(x: 320, y: 740), startRadius: 0,
                               endCenter: CGPoint(x: 320, y: 740), endRadius: 600, options: [])
        ctx.restoreGState()

        ctx.setFillColor(.white)
        drawEqualizer(ctx, refW: 720)
    }
    return ctx.makeImage()!
}

// MARK: - Write the iconset + build the .icns

func writePNG(_ image: CGImage, to url: URL) {
    let rep = NSBitmapImageRep(cgImage: image)
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: url)
}

// `#filePath` is this script's own path — robust no matter how it's invoked (cwd, symlink, PATH).
let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()    // Scripts/
    .deletingLastPathComponent()    // SpeakTypeMac/
let bundle = root.appendingPathComponent("AppBundle")
let iconset = bundle.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

// macOS .icns expects these exact filenames/sizes.
let sizes: [(name: String, px: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for entry in sizes {
    writePNG(renderAppIcon(size: entry.px), to: iconset.appendingPathComponent("\(entry.name).png"))
}

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path,
                  "-o", bundle.appendingPathComponent("AppIcon.icns").path]
try! task.run()
task.waitUntilExit()
print(task.terminationStatus == 0
      ? "Wrote AppBundle/AppIcon.icns"
      : "iconutil failed (\(task.terminationStatus))")

// MARK: - Menu-bar template glyph (vector PDF, black-on-transparent → macOS tints it)

let pdfData = NSMutableData()
let consumer = CGDataConsumer(data: pdfData as CFMutableData)!
var mediaBox = CGRect(x: 0, y: 0, width: 1000, height: 1000)
let pdf = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)!
pdf.beginPDFPage(nil)
pdf.setFillColor(CGColor(gray: 0, alpha: 1))
// refW 1000 → the tallest bar nearly fills the box, so the glyph reads big in the menu bar.
drawEqualizer(pdf, refW: 1000)
pdf.endPDFPage()
pdf.closePDF()
try! (pdfData as Data).write(to: bundle.appendingPathComponent("MenuBarIcon.pdf"))
print("Wrote AppBundle/MenuBarIcon.pdf")
