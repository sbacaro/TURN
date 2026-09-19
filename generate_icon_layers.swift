import AppKit
import CoreGraphics

// Generates the layered source PNGs for TURN's Liquid Glass icon.
// Layer order (back to front):
//   1. Background wash  — deep blue gradient squircle-safe canvas
//   2. Mid plate        — frosted fader tracks (3D depth under glass)
//   3. Foreground mark  — the SF Symbol "slider.vertical.3" fader glyph
//
// Files follow Icon Composer's expected layer import naming.

let accentR: CGFloat = 0.173, accentG: CGFloat = 0.573, accentB: CGFloat = 0.976
let size: CGFloat = 1024

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}

func context(size: CGFloat) -> CGContext {
    CGContext(
        data: nil,
        width: Int(size), height: Int(size),
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
}

func save(_ ctx: CGContext, _ name: String) {
    let img = ctx.makeImage()!
    let rep = NSBitmapImageRep(cgImage: img)
    let png = rep.representation(using: .png, properties: [:])!
    try! png.write(to: URL(fileURLWithPath: "TURN/Assets.xcassets/AppIcon.icon/\(name)"))
    print("wrote \(name)")
}

// MARK: - Layer 1: Background wash (opaque gradient)

let bgCtx = context(size: size)
let gradient = CGGradient(
    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
    colors: [rgb(0.16, 0.52, 0.95), rgb(0.04, 0.14, 0.30)] as CFArray,
    locations: [0, 1]
)!
bgCtx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size), end: CGPoint(x: 0, y: 0), options: [])
save(bgCtx, "background.png")

// MARK: - Layer 2: Mid plate (fader tracks, semi-transparent white)

let midCtx = context(size: size)
midCtx.setFillColor(rgb(1, 1, 1, 0.28))
let trackWidth: CGFloat = 44
let slotCount = 8
let slotSpacing = size / CGFloat(slotCount)
for slot in 0..<slotCount {
    let cx = slotSpacing * CGFloat(slot) + slotSpacing / 2
    let rect = CGRect(x: cx - trackWidth / 2, y: size * 0.14, width: trackWidth, height: size * 0.72)
    let path = CGPath(roundedRect: rect, cornerWidth: trackWidth / 2, cornerHeight: trackWidth / 2, transform: nil)
    midCtx.addPath(path)
    midCtx.fillPath()
}
save(midCtx, "mid-plate.png")

// MARK: - Layer 3: Foreground mark (fader caps + center rail, solid accent)

let fgCtx = context(size: size)

// Accent caps — one per track, staggered like a real mixer at rest
fgCtx.setFillColor(rgb(accentR, accentG, accentB, 1))
fgCtx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: rgb(0, 0, 0, 0.35))
let capWidth: CGFloat = 88
let capHeight: CGFloat = 128
let capOffsets: [CGFloat] = [0.58, 0.34, 0.72, 0.26, 0.64, 0.30, 0.70, 0.38]
for (slot, offset) in capOffsets.enumerated() {
    let cx = slotSpacing * CGFloat(slot) + slotSpacing / 2
    let cy = size * (0.14 + (0.72 - offset * 0.72))
    let rect = CGRect(x: cx - capWidth / 2, y: cy, width: capWidth, height: capHeight)
    let path = CGPath(roundedRect: rect, cornerWidth: 22, cornerHeight: 22, transform: nil)
    fgCtx.addPath(path)
    fgCtx.fillPath()
}

// Bright center line on each cap (highlight detail)
fgCtx.setShadow(offset: .zero, blur: 0, color: nil)
fgCtx.setFillColor(rgb(1, 1, 1, 0.9))
for (slot, offset) in capOffsets.enumerated() {
    let cx = slotSpacing * CGFloat(slot) + slotSpacing / 2
    let cy = size * (0.14 + (0.72 - offset * 0.72))
    let rect = CGRect(x: cx - 6, y: cy + capHeight * 0.32, width: 12, height: capHeight * 0.36)
    let path = CGPath(roundedRect: rect, cornerWidth: 6, cornerHeight: 6, transform: nil)
    fgCtx.addPath(path)
    fgCtx.fillPath()
}
save(fgCtx, "foreground.png")

print("All layers written.")
