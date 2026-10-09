// Renders the Pith app icon (tree rings around an amber pith) into an .icns.
// Usage: swift scripts/make-icon.swift <out.icns>
import AppKit

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext

    // macOS icon grid: 824/1024 body with ~185 corner radius.
    let inset = s * 100 / 1024
    let body = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let shape = CGPath(roundedRect: body, cornerWidth: s * 185 / 1024, cornerHeight: s * 185 / 1024, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    ctx.addPath(shape); ctx.setFillColor(NSColor.black.cgColor); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(shape); ctx.clip()
    let bg = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                        colors: [NSColor(srgbRed: 0.17, green: 0.24, blue: 0.19, alpha: 1).cgColor,
                                 NSColor(srgbRed: 0.09, green: 0.13, blue: 0.10, alpha: 1).cgColor] as CFArray,
                        locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: s), end: CGPoint(x: 0, y: 0), options: [])

    let wood: [(CGFloat, CGFloat, CGFloat)] = [(0x7A, 0x42, 0x20), (0x9A, 0x5A, 0x2B), (0xB8, 0x74, 0x3A),
                                              (0xC8, 0x8C, 0x4C), (0xD9, 0xA8, 0x66), (0xE2, 0xC2, 0x8A), (0xEA, 0xD9, 0xB5)]
    let c = CGPoint(x: s / 2, y: s / 2)
    let count = 10
    var radii: [CGFloat] = []
    var r: CGFloat = 0.09, step: CGFloat = 0.02
    for _ in 0..<count { radii.append(r); r += step; step *= 1.34 }
    let scale = (body.width * 0.40) / radii.last!
    for (k, rr) in radii.enumerated() {
        let t = CGFloat(k) / CGFloat(count - 1)
        let w = wood[min(Int(t * CGFloat(wood.count - 1) + 0.5), wood.count - 1)]
        ctx.setStrokeColor(NSColor(srgbRed: w.0 / 255, green: w.1 / 255, blue: w.2 / 255, alpha: 0.6 + 0.4 * t).cgColor)
        ctx.setLineWidth(s * (0.006 + 0.010 * t))
        let path = CGMutablePath()
        for st in 0...240 {
            let a = Double(st) / 240 * 2 * .pi
            let wob = 1 + 0.02 * sin(3 * a + Double(k)) + 0.012 * sin(5 * a + 2 * Double(k))
            let p = CGPoint(x: c.x + rr * scale * CGFloat(wob * cos(a)), y: c.y + rr * scale * CGFloat(wob * sin(a)))
            st == 0 ? path.move(to: p) : path.addLine(to: p)
        }
        ctx.addPath(path); ctx.strokePath()
    }
    let dot = body.width * 0.035
    ctx.setFillColor(NSColor(srgbRed: 0xC9 / 255, green: 0x77 / 255, blue: 0x2E / 255, alpha: 1).cgColor)
    ctx.fillEllipse(in: CGRect(x: c.x - dot, y: c.y - dot, width: dot * 2, height: dot * 2))

    // Glassy top sheen.
    let sheen = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                           colors: [NSColor.white.withAlphaComponent(0.14).cgColor, NSColor.white.withAlphaComponent(0).cgColor] as CFArray,
                           locations: [0, 1])!
    ctx.drawLinearGradient(sheen, start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.midY), options: [])
    ctx.restoreGState()
    ctx.addPath(shape)
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.12).cgColor)
    ctx.setLineWidth(s * 0.003)
    ctx.strokePath()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Pith.icns"
let set = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Pith.iconset")
try? FileManager.default.removeItem(at: set)
try! FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: set.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: set.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
try! render(1024).write(to: URL(fileURLWithPath: out).deletingPathExtension().appendingPathExtension("png"))
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", set.path, "-o", out]
try! p.run(); p.waitUntilExit()
print("wrote \(out)")
