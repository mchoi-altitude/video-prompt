#!/usr/bin/env swift
// Draws the app icon and writes Resources/AppIcon.icns. Run from the repo root after changing the
// artwork: swift scripts/make-app-icon.swift
// Keep it matching the menu-bar icon in Sources/VideoPrompt/MenuIcon.swift.
import AppKit

/// Drawn on a 128-unit grid, origin top-left. The tile leaves macOS's standard margin around it.
func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    let scale = CGFloat(pixels) / 128
    ctx.translateBy(x: 0, y: CGFloat(pixels))
    ctx.scaleBy(x: scale, y: -scale)

    // The tile: the same dark as the control bar.
    let tile = CGPath(roundedRect: CGRect(x: 12, y: 12, width: 104, height: 104), cornerWidth: 24, cornerHeight: 24, transform: nil)
    ctx.saveGState()
    ctx.addPath(tile)
    ctx.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
        CGColor(srgbRed: 0x2D / 255, green: 0x2E / 255, blue: 0x35 / 255, alpha: 1),
        CGColor(srgbRed: 0x13 / 255, green: 0x14 / 255, blue: 0x18 / 255, alpha: 1),
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 64, y: 12), end: CGPoint(x: 64, y: 116), options: [])
    ctx.restoreGState()

    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)

    // Selection corners.
    let corners = CGMutablePath()
    func corner(_ a: CGPoint, _ bend: CGPoint, _ b: CGPoint) {
        corners.move(to: a)
        corners.addArc(tangent1End: bend, tangent2End: b, radius: 6)
        corners.addLine(to: b)
    }
    corner(CGPoint(x: 34, y: 52), CGPoint(x: 34, y: 34), CGPoint(x: 52, y: 34))
    corner(CGPoint(x: 76, y: 34), CGPoint(x: 94, y: 34), CGPoint(x: 94, y: 52))
    corner(CGPoint(x: 94, y: 76), CGPoint(x: 94, y: 94), CGPoint(x: 76, y: 94))
    corner(CGPoint(x: 52, y: 94), CGPoint(x: 34, y: 94), CGPoint(x: 34, y: 76))
    ctx.addPath(corners)
    ctx.setStrokeColor(CGColor(srgbRed: 0xF3 / 255, green: 0xF3 / 255, blue: 0xF5 / 255, alpha: 1))
    ctx.setLineWidth(6)
    ctx.strokePath()

    // The hand-drawn V, in the red of the drawing marks.
    let v = CGMutablePath()
    v.move(to: CGPoint(x: 43, y: 49))
    v.addCurve(to: CGPoint(x: 62, y: 84), control1: CGPoint(x: 47, y: 61), control2: CGPoint(x: 54, y: 75))
    v.addCurve(to: CGPoint(x: 68.4, y: 84), control1: CGPoint(x: 64, y: 86.4), control2: CGPoint(x: 66.6, y: 86.4))
    v.addCurve(to: CGPoint(x: 90, y: 41), control1: CGPoint(x: 75, y: 74), control2: CGPoint(x: 81, y: 58))
    ctx.addPath(v)
    ctx.setStrokeColor(CGColor(srgbRed: 0xE5 / 255, green: 0x48 / 255, blue: 0x4D / 255, alpha: 1))
    ctx.setLineWidth(8)
    ctx.strokePath()

    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let set = fm.temporaryDirectory.appending(path: "AppIcon-\(UUID().uuidString).iconset")
try fm.createDirectory(at: set, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: set) }
for points in [16, 32, 128, 256, 512] {
    try render(pixels: points).write(to: set.appending(path: "icon_\(points)x\(points).png"))
    try render(pixels: points * 2).write(to: set.appending(path: "icon_\(points)x\(points)@2x.png"))
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", set.path, "-o", "Resources/AppIcon.icns"]
try iconutil.run()
iconutil.waitUntilExit()
exit(iconutil.terminationStatus)
