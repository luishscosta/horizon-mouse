// Renders the app icon as vector art.
// Run: swift scripts/make-icon.swift /tmp/AppIcon.iconset && iconutil -c icns /tmp/AppIcon.iconset -o Resources/AppIcon.icns
import AppKit

func rgb(_ hex: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 0xff) / 255, green: CGFloat(hex >> 8 & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: 1)
}

let backgroundTop = rgb(0x5B2BB0), backgroundBottom = rgb(0x2E1166) // deep purple tile
let accentTop = rgb(0xD2B6FF), accentBottom = rgb(0xA77BFF)         // light purple arc, line, arrows
let outline = rgb(0x1E1235), bodyTop = rgb(0xFFFFFF), bodyBottom = rgb(0xDCD8E8), wheel = rgb(0x7C3AED)

func linear(_ ctx: CGContext, _ top: CGColor, _ bottom: CGColor, from y0: CGFloat, to y1: CGFloat) {
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [top, bottom] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: y0), end: CGPoint(x: 0, y: y1), options: [])
}

func render(_ side: Int) -> Data {
    let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // Work in a 1024 canvas with the origin at the top left.
    ctx.scaleBy(x: CGFloat(side) / 1024, y: CGFloat(side) / 1024)
    ctx.translateBy(x: 0, y: 1024)
    ctx.scaleBy(x: 1, y: -1)

    // macOS icon grid: 824 tile centered on the 1024 canvas, soft drop shadow.
    let tile = CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824), cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 10), blur: 20, color: CGColor(gray: 0, alpha: 0.3))
    ctx.addPath(tile); ctx.setFillColor(backgroundBottom); ctx.fillPath()
    ctx.restoreGState()
    ctx.addPath(tile); ctx.clip()
    linear(ctx, backgroundTop, backgroundBottom, from: 100, to: 924)

    // Artwork, centered at (512, 512); the horizon line sits at y = 600.
    let horizon: CGFloat = 600
    // Arc (half disc) rising behind the mouse.
    ctx.saveGState()
    ctx.addArc(center: CGPoint(x: 512, y: horizon), radius: 285, startAngle: .pi, endAngle: 0, clockwise: false)
    ctx.closePath(); ctx.clip()
    linear(ctx, accentTop, accentBottom, from: horizon - 285, to: horizon)
    ctx.restoreGState()
    // Horizon line with arrowheads, running edge to edge.
    ctx.setFillColor(accentBottom)
    ctx.fill(CGRect(x: 90, y: horizon - 6, width: 844, height: 12))
    for (tip, base) in [(CGFloat(170), CGFloat(232)), (854, 792)] {
        ctx.move(to: CGPoint(x: tip, y: horizon))
        ctx.addLine(to: CGPoint(x: base, y: horizon - 46))
        ctx.addLine(to: CGPoint(x: base, y: horizon + 46))
        ctx.closePath()
    }
    ctx.setFillColor(accentTop); ctx.fillPath()

    // Mouse: outlined capsule with button split and scroll wheel.
    let mouse = CGRect(x: 392, y: 323, width: 240, height: 380)
    let mousePath = CGPath(roundedRect: mouse, cornerWidth: 120, cornerHeight: 130, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 12), blur: 24, color: CGColor(gray: 0, alpha: 0.35))
    ctx.addPath(mousePath); ctx.setFillColor(outline); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(mousePath); ctx.clip()
    linear(ctx, bodyTop, bodyBottom, from: mouse.minY, to: mouse.maxY)
    ctx.restoreGState()
    ctx.setStrokeColor(outline); ctx.setLineCap(.round)
    ctx.setLineWidth(16); ctx.addPath(mousePath); ctx.strokePath()
    ctx.setLineWidth(12)
    ctx.move(to: CGPoint(x: mouse.minX, y: 478)); ctx.addLine(to: CGPoint(x: mouse.maxX, y: 478))
    ctx.move(to: CGPoint(x: 512, y: mouse.minY)); ctx.addLine(to: CGPoint(x: 512, y: 478))
    ctx.strokePath()
    let wheelPath = CGPath(roundedRect: CGRect(x: 490, y: 363, width: 44, height: 76), cornerWidth: 22, cornerHeight: 22, transform: nil)
    ctx.addPath(wheelPath); ctx.setFillColor(wheel); ctx.fillPath()
    ctx.addPath(wheelPath); ctx.setLineWidth(10); ctx.strokePath()

    return NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
}

let dir = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "/tmp/AppIcon.iconset")
try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try render(base).write(to: dir.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(base * 2).write(to: dir.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
