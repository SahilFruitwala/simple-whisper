// Renders the app icon and menu-bar glyph into SimpleWisper/Assets.xcassets.
// Run: swift scripts/make-icons.swift
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let assets = root.appendingPathComponent("SimpleWisper/Assets.xcassets")
let amber = NSColor(calibratedRed: 0.95, green: 0.66, blue: 0.10, alpha: 1)
let cream = NSColor(calibratedRed: 0.97, green: 0.93, blue: 0.85, alpha: 1)

// Waveform bar heights (fraction of max), symmetric around the centre bar.
let bars: [CGFloat] = [0.38, 0.72, 1.0, 0.72, 0.38]

func png(_ size: Int, draw: (CGRect) -> Void) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw(CGRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

func drawWave(in rect: CGRect, color: (Int) -> NSColor) {
    let count = CGFloat(bars.count)
    let gap = rect.width / (count * 2 - 1)
    for (i, h) in bars.enumerated() {
        let height = max(gap, rect.height * h)
        let bar = CGRect(x: rect.minX + CGFloat(i) * gap * 2, y: rect.midY - height / 2, width: gap, height: height)
        color(i).setFill()
        NSBezierPath(roundedRect: bar, xRadius: gap / 2, yRadius: gap / 2).fill()
    }
}

func appIcon(_ r: CGRect) {
    let s = r.width
    // macOS icon grid: 824/1024 body with soft shadow.
    let body = r.insetBy(dx: s * 0.098, dy: s * 0.098)
    let radius = body.width * 0.225
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.012)
    shadow.shadowBlurRadius = s * 0.03
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    let path = NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)
    NSGradient(starting: NSColor(calibratedRed: 0.20, green: 0.18, blue: 0.15, alpha: 1),
               ending: NSColor(calibratedRed: 0.08, green: 0.07, blue: 0.06, alpha: 1))!.draw(in: path, angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // Inner capsule echoing the HUD.
    let capsule = CGRect(x: body.minX + body.width * 0.12, y: body.midY - body.height * 0.2,
                         width: body.width * 0.76, height: body.height * 0.4)
    NSColor.white.withAlphaComponent(0.06).setFill()
    NSBezierPath(roundedRect: capsule, xRadius: capsule.height / 2, yRadius: capsule.height / 2).fill()

    // On-air dot.
    let dot = capsule.height * 0.22
    let dotRect = CGRect(x: capsule.minX + capsule.height * 0.36, y: capsule.midY - dot / 2, width: dot, height: dot)
    let glow = NSShadow()
    glow.shadowColor = amber.withAlphaComponent(0.8)
    glow.shadowBlurRadius = s * 0.025
    NSGraphicsContext.saveGraphicsState()
    glow.set()
    amber.setFill()
    NSBezierPath(ovalIn: dotRect).fill()
    NSGraphicsContext.restoreGraphicsState()

    let waveRect = CGRect(x: dotRect.maxX + capsule.height * 0.32, y: capsule.minY + capsule.height * 0.2,
                          width: capsule.maxX - dotRect.maxX - capsule.height * 0.75, height: capsule.height * 0.6)
    drawWave(in: waveRect) { i in i == 2 ? amber : cream }
}

func menuGlyph(_ r: CGRect) {
    // Template image: dot + short waveform, black on transparent.
    let s = r.width
    NSColor.black.setFill()
    let dot = s * 0.2
    NSBezierPath(ovalIn: CGRect(x: s * 0.04, y: (s - dot) / 2, width: dot, height: dot)).fill()
    drawWave(in: CGRect(x: s * 0.34, y: s * 0.14, width: s * 0.62, height: s * 0.72)) { _ in .black }
}

func write(_ data: Data, _ path: String) {
    let url = assets.appendingPathComponent(path)
    try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try! data.write(to: url)
}

func json(_ object: Any, _ path: String) {
    write(try! JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]), path)
}

json(["info": ["author": "xcode", "version": 1]], "Contents.json")

var images: [[String: String]] = []
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = base * scale
        let name = "icon_\(base)x\(base)\(scale == 2 ? "@2x" : "").png"
        write(png(px, draw: appIcon), "AppIcon.appiconset/\(name)")
        images.append(["idiom": "mac", "size": "\(base)x\(base)", "scale": "\(scale)x", "filename": name])
    }
}
json(["images": images, "info": ["author": "xcode", "version": 1]], "AppIcon.appiconset/Contents.json")

var glyphs: [[String: String]] = []
for scale in [1, 2, 3] {
    let name = "menubar@\(scale)x.png"
    write(png(18 * scale, draw: menuGlyph), "MenuBarIcon.imageset/\(name)")
    glyphs.append(["idiom": "universal", "scale": "\(scale)x", "filename": name])
}
json(["images": glyphs, "info": ["author": "xcode", "version": 1],
      "properties": ["template-rendering-intent": "template"]], "MenuBarIcon.imageset/Contents.json")

write(png(1024, draw: appIcon), "../../build/icon-preview.png")
print("Icons written to \(assets.path)")
