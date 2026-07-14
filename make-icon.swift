import AppKit

// Brand teal/cyan, top→bottom gradient (matches DesignKit's Brand).
let top = NSColor(srgbRed: 0.07, green: 0.71, blue: 0.647, alpha: 1)   // #12B5A5
let bottom = NSColor(srgbRed: 0.055, green: 0.486, blue: 0.51, alpha: 1) // #0E7C82

func tint(_ image: NSImage, _ color: NSColor) -> NSImage {
    let out = NSImage(size: image.size)
    out.lockFocus()
    let rect = NSRect(origin: .zero, size: image.size)
    image.draw(in: rect)
    color.set()
    rect.fill(using: .sourceAtop)
    out.unlockFocus()
    return out
}

func makeIcon(_ px: Int) -> Data {
    let size = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // macOS-style rounded tile with ~10% margin.
    let margin = size * 0.10
    let tile = NSRect(x: margin, y: margin, width: size - margin * 2, height: size - margin * 2)
    let radius = tile.width * 0.2237

    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: tile, xRadius: radius, yRadius: radius).addClip()
    NSGradient(colors: [top, bottom])!.draw(in: tile, angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // White "camera viewfinder" glyph, centered, with a soft shadow.
    if let base = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: nil) {
        let conf = NSImage.SymbolConfiguration(pointSize: size * 0.42, weight: .semibold)
        let glyph = tint(base.withSymbolConfiguration(conf) ?? base, .white)
        let target = tile.width * 0.56
        let s = glyph.size
        let scale = target / max(s.width, s.height)
        let w = s.width * scale, h = s.height * scale
        let rect = NSRect(x: tile.midX - w / 2, y: tile.midY - h / 2, width: w, height: h)

        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.20)
        shadow.shadowOffset = NSSize(width: 0, height: -size * 0.006)
        shadow.shadowBlurRadius = size * 0.014
        NSGraphicsContext.saveGraphicsState()
        shadow.set()
        glyph.draw(in: rect)
        NSGraphicsContext.restoreGraphicsState()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let iconset = "Screenly.iconset"
try? FileManager.default.removeItem(atPath: iconset)
try! FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)

let map: [(Int, [String])] = [
    (16, ["icon_16x16.png"]),
    (32, ["icon_16x16@2x.png", "icon_32x32.png"]),
    (64, ["icon_32x32@2x.png"]),
    (128, ["icon_128x128.png"]),
    (256, ["icon_128x128@2x.png", "icon_256x256.png"]),
    (512, ["icon_256x256@2x.png", "icon_512x512.png"]),
    (1024, ["icon_512x512@2x.png"]),
]
for (px, names) in map {
    let data = makeIcon(px)
    for n in names { try! data.write(to: URL(fileURLWithPath: "\(iconset)/\(n)")) }
}

// Preview for visual check.
try! makeIcon(512).write(to: URL(fileURLWithPath: "icon-preview.png"))
print("iconset + preview gerados")
