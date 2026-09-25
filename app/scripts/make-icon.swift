// Draws Plumb's app icon ("Bob": a graphite plumb weight on paper) at every macOS size
// and packs them into AppIcon.icns. Run: swift scripts/make-icon.swift <output-dir>
import AppKit

let paper = CGColor(red: 0xf4 / 255, green: 0xf5 / 255, blue: 0xf7 / 255, alpha: 1)
let graphite = CGColor(red: 0x1e / 255, green: 0x22 / 255, blue: 0x28 / 255, alpha: 1)

/// The icon on a 1024-point canvas with y pointing down, matching the design file.
func draw(_ ctx: CGContext) {
    ctx.translateBy(x: 0, y: 1024)
    ctx.scaleBy(x: 1, y: -1)
    let tile = CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824),
                      cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.addPath(tile)
    ctx.setFillColor(paper)
    ctx.fillPath()
    ctx.addPath(tile)
    ctx.setStrokeColor(CGColor(gray: 0, alpha: 0.07))
    ctx.setLineWidth(2)
    ctx.strokePath()

    // The plumb weight: a teardrop pointing down, centred at (512, 520), scaled 1.9.
    ctx.translateBy(x: 512, y: 520)
    ctx.scaleBy(x: 1.9, y: 1.9)
    let bob = CGMutablePath()
    bob.move(to: CGPoint(x: 0, y: -90))
    bob.addCurve(to: CGPoint(x: 78, y: -8), control1: CGPoint(x: 52, y: -90), control2: CGPoint(x: 78, y: -48))
    bob.addCurve(to: CGPoint(x: 0, y: 130), control1: CGPoint(x: 78, y: 50), control2: CGPoint(x: 30, y: 88))
    bob.addCurve(to: CGPoint(x: -78, y: -8), control1: CGPoint(x: -30, y: 88), control2: CGPoint(x: -78, y: 50))
    bob.addCurve(to: CGPoint(x: 0, y: -90), control1: CGPoint(x: -78, y: -48), control2: CGPoint(x: -52, y: -90))
    bob.closeSubpath()
    ctx.addPath(bob)
    ctx.setFillColor(graphite)
    ctx.fillPath()
}

func png(pixels: Int) -> Data {
    let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    draw(ctx)
    return NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
}

let out = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".")
let iconset = out.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    try png(pixels: size).write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try png(pixels: size * 2).write(to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", out.appendingPathComponent("AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
try FileManager.default.removeItem(at: iconset)
try png(pixels: 1024).write(to: out.appendingPathComponent("AppIcon-1024.png"))
print("Wrote AppIcon.icns and AppIcon-1024.png to \(out.path)")
