#!/usr/bin/env swift
import AppKit

// Draws the Nomen icon: a screenshot card with a name tag hanging off it, on the Jorvik
// brand plate. Usage: swift generate_icon.swift Resources/Nomen.iconset
// CG coordinate origin: bottom-left.

let brandTop    = CGColor(srgbRed: 0.05, green: 0.32, blue: 0.58, alpha: 1)   // #0D5294
let brandBottom = CGColor(srgbRed: 0.00, green: 0.20, blue: 0.42, alpha: 1)   // #00356B
let card        = CGColor(srgbRed: 0.97, green: 0.98, blue: 1.00, alpha: 1)
let cardInk     = CGColor(srgbRed: 0.55, green: 0.66, blue: 0.80, alpha: 1)   // pale blue lines
let silver      = CGColor(srgbRed: 0.80, green: 0.84, blue: 0.90, alpha: 1)   // cool, slightly blue
let silverEdge  = CGColor(srgbRed: 0.62, green: 0.68, blue: 0.77, alpha: 1)

func drawIcon(ctx: CGContext, s: CGFloat) {
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!

    // 1. Brand plate: full bleed, radius 0.22, vertical gradient.
    let plate = CGPath(roundedRect: CGRect(x: 0, y: 0, width: s, height: s),
                       cornerWidth: s * 0.22, cornerHeight: s * 0.22, transform: nil)
    ctx.saveGState()
    ctx.addPath(plate)
    ctx.clip()
    let grad = CGGradient(colorsSpace: cs, colors: [brandTop, brandBottom] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: s / 2, y: s), end: CGPoint(x: s / 2, y: 0), options: [])
    ctx.restoreGState()

    // 2. The screenshot: a white card, slightly up and left, with soft shadow.
    let cardRect = CGRect(x: s * 0.17, y: s * 0.30, width: s * 0.58, height: s * 0.46)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.015), blur: s * 0.04,
                  color: CGColor(gray: 0, alpha: 0.35))
    ctx.addPath(CGPath(roundedRect: cardRect, cornerWidth: s * 0.04, cornerHeight: s * 0.04, transform: nil))
    ctx.setFillColor(card)
    ctx.fillPath()
    ctx.restoreGState()

    // Crop marks in the card's corners: it reads as a capture, not a document.
    ctx.saveGState()
    ctx.setStrokeColor(cardInk)
    ctx.setLineWidth(max(1, s * 0.022))
    ctx.setLineCap(.round)
    let inset = s * 0.05, arm = s * 0.07
    let r = cardRect.insetBy(dx: inset, dy: inset)
    for (corner, dx, dy) in [(CGPoint(x: r.minX, y: r.maxY), 1.0, -1.0),
                             (CGPoint(x: r.maxX, y: r.maxY), -1.0, -1.0),
                             (CGPoint(x: r.minX, y: r.minY), 1.0, 1.0)] {
        ctx.move(to: CGPoint(x: corner.x + arm * dx, y: corner.y))
        ctx.addLine(to: corner)
        ctx.addLine(to: CGPoint(x: corner.x, y: corner.y + arm * dy))
    }
    ctx.strokePath()
    ctx.restoreGState()

    // 3. The name tag, tilted, hanging over the card's lower-right corner.
    ctx.saveGState()
    ctx.translateBy(x: s * 0.66, y: s * 0.30)
    ctx.rotate(by: -0.42)
    let w = s * 0.40, h = s * 0.20, notch = h * 0.5
    let tag = CGMutablePath()
    tag.move(to: CGPoint(x: -w / 2 + notch, y: h / 2))
    tag.addLine(to: CGPoint(x: w / 2 - s * 0.03, y: h / 2))
    tag.addQuadCurve(to: CGPoint(x: w / 2, y: h / 2 - s * 0.03), control: CGPoint(x: w / 2, y: h / 2))
    tag.addLine(to: CGPoint(x: w / 2, y: -h / 2 + s * 0.03))
    tag.addQuadCurve(to: CGPoint(x: w / 2 - s * 0.03, y: -h / 2), control: CGPoint(x: w / 2, y: -h / 2))
    tag.addLine(to: CGPoint(x: -w / 2 + notch, y: -h / 2))
    tag.addLine(to: CGPoint(x: -w / 2, y: 0))
    tag.closeSubpath()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03,
                  color: CGColor(gray: 0, alpha: 0.35))
    ctx.addPath(tag)
    ctx.setFillColor(silver)
    ctx.fillPath()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
    ctx.addPath(tag)
    ctx.setStrokeColor(silverEdge)
    ctx.setLineWidth(max(0.5, s * 0.008))
    ctx.strokePath()

    // The tag's hole, punched through to the plate colour.
    let holeR = h * 0.13
    ctx.addEllipse(in: CGRect(x: -w / 2 + notch * 0.75 - holeR, y: -holeR, width: holeR * 2, height: holeR * 2))
    ctx.setFillColor(brandBottom)
    ctx.fillPath()

    // Two lines of "writing" on the tag: the name.
    ctx.setStrokeColor(brandBottom)
    ctx.setLineCap(.round)
    ctx.setLineWidth(max(1, s * 0.022))
    let x0 = -w / 2 + notch * 1.35, x1 = w / 2 - s * 0.05
    ctx.move(to: CGPoint(x: x0, y: h * 0.14)); ctx.addLine(to: CGPoint(x: x1, y: h * 0.14))
    ctx.move(to: CGPoint(x: x0, y: -h * 0.16)); ctx.addLine(to: CGPoint(x: x0 + (x1 - x0) * 0.6, y: -h * 0.16))
    ctx.strokePath()
    ctx.restoreGState()
}

func renderIcon(pixels: Int) -> Data? {
    guard let bmp = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
          let ctx = NSGraphicsContext(bitmapImageRep: bmp)?.cgContext else { return nil }
    drawIcon(ctx: ctx, s: CGFloat(pixels))
    return bmp.representation(using: .png, properties: [:])
}

let destDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath
try? FileManager.default.createDirectory(atPath: destDir, withIntermediateDirectories: true)
let sizes: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32), ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256), ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512), ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]
for (filename, pixels) in sizes {
    if let data = renderIcon(pixels: pixels) {
        try! data.write(to: URL(fileURLWithPath: destDir).appendingPathComponent(filename))
        print("✓  \(filename)  (\(pixels)px)")
    } else {
        print("✗  Failed: \(filename)")
    }
}
