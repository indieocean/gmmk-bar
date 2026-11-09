// Draws the app icon and writes Resources/AppIcon.icns.
// Usage: swift scripts/make-icon.swift   (run from the repo root)
import AppKit

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let s = CGFloat(px) / 1024
    ctx.scaleBy(x: s, y: s)

    // macOS icon grid: 824pt body centred in a 1024 canvas.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let bodyPath = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

    // Drop shadow + dark background
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.45).cgColor)
    ctx.addPath(bodyPath)
    ctx.setFillColor(NSColor(red: 0.05, green: 0.06, blue: 0.09, alpha: 1).cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(bodyPath); ctx.clip()
    let cs = CGColorSpaceCreateDeviceRGB()
    let bg = CGGradient(colorsSpace: cs, colors: [
        NSColor(red: 0.09, green: 0.10, blue: 0.16, alpha: 1).cgColor,
        NSColor(red: 0.04, green: 0.05, blue: 0.08, alpha: 1).cgColor] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])

    let rainbow: [NSColor] = [
        .init(red: 1.00, green: 0.23, blue: 0.19, alpha: 1), .init(red: 1.00, green: 0.62, blue: 0.04, alpha: 1),
        .init(red: 1.00, green: 0.84, blue: 0.04, alpha: 1), .init(red: 0.20, green: 0.84, blue: 0.29, alpha: 1),
        .init(red: 0.39, green: 0.82, blue: 1.00, alpha: 1), .init(red: 0.37, green: 0.36, blue: 0.90, alpha: 1),
        .init(red: 0.75, green: 0.35, blue: 0.95, alpha: 1)]
    let rgb = CGGradient(colorsSpace: cs, colors: rainbow.map(\.cgColor) as CFArray,
                         locations: (0..<rainbow.count).map { CGFloat($0) / CGFloat(rainbow.count - 1) })!

    // Underglow beneath the keyboard
    let kb = CGRect(x: 192, y: 334, width: 640, height: 356)
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 90, color: NSColor(red: 0.45, green: 0.4, blue: 1, alpha: 0.9).cgColor)
    ctx.addPath(CGPath(roundedRect: kb.insetBy(dx: 20, dy: 10), cornerWidth: 60, cornerHeight: 60, transform: nil))
    ctx.setFillColor(NSColor(red: 0.4, green: 0.35, blue: 1, alpha: 0.35).cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    // Keyboard case
    let casePath = CGPath(roundedRect: kb, cornerWidth: 56, cornerHeight: 56, transform: nil)
    ctx.addPath(casePath)
    ctx.setFillColor(NSColor(red: 0.13, green: 0.14, blue: 0.20, alpha: 1).cgColor)
    ctx.fillPath()

    // Keys: lit with the rainbow gradient running left to right.
    let pad: CGFloat = 34, gap: CGFloat = 16, cols = 7
    let keyW = (kb.width - 2 * pad - gap * CGFloat(cols - 1)) / CGFloat(cols)
    let keyH: CGFloat = 60
    var keys: [CGRect] = []
    let top = kb.maxY - pad - keyH
    for row in 0..<3 {
        let y = top - CGFloat(row) * (keyH + gap)
        for c in 0..<cols {
            keys.append(CGRect(x: kb.minX + pad + CGFloat(c) * (keyW + gap), y: y, width: keyW, height: keyH))
        }
    }
    // Space bar row
    let spaceY = top - 3 * (keyH + gap)
    keys.append(CGRect(x: kb.minX + pad, y: spaceY, width: keyW, height: keyH))
    keys.append(CGRect(x: kb.minX + pad + keyW + gap, y: spaceY, width: 5 * keyW + 4 * gap, height: keyH))
    keys.append(CGRect(x: kb.maxX - pad - keyW, y: spaceY, width: keyW, height: keyH))

    let keysPath = CGMutablePath()
    for k in keys { keysPath.addPath(CGPath(roundedRect: k, cornerWidth: 12, cornerHeight: 12, transform: nil)) }

    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 22, color: NSColor.white.withAlphaComponent(0.35).cgColor)
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    ctx.addPath(keysPath); ctx.clip()
    ctx.drawLinearGradient(rgb, start: CGPoint(x: kb.minX, y: kb.maxY), end: CGPoint(x: kb.maxX, y: kb.minY),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.endTransparencyLayer()
    ctx.restoreGState()

    // Subtle top highlight on the body
    ctx.addPath(bodyPath)
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.08).cgColor)
    ctx.setLineWidth(4)
    ctx.strokePath()
    ctx.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(at: iconset)
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try render(base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
try fm.createDirectory(atPath: "Resources", withIntermediateDirectories: true)
try render(1024).write(to: URL(fileURLWithPath: "docs/icon.png"))

let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try p.run(); p.waitUntilExit()
print(p.terminationStatus == 0 ? "Wrote Resources/AppIcon.icns and docs/icon.png" : "iconutil failed")
