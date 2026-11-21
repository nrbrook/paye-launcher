// Draws the app icon (a green rounded square with "PAYE" and a web globe mark)
// and writes an .iconset folder. Usage: swift make_icon.swift <output.iconset>
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    let inset = s * 0.1
    let rect = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let path = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)
    let gradient = NSGradient(starting: NSColor(srgbRed: 0.0, green: 0.62, blue: 0.52, alpha: 1),
                              ending: NSColor(srgbRed: 0.0, green: 0.43, blue: 0.36, alpha: 1))!
    gradient.draw(in: path, angle: -90)

    let font = NSFont.systemFont(ofSize: rect.width * 0.26, weight: .heavy)
    let text = NSAttributedString(string: "PAYE", attributes: [.font: font, .foregroundColor: NSColor.white])
    let size = text.size()
    text.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2 + rect.height * 0.08))

    // Small globe under the text, to mark the web version.
    let r = rect.width * 0.12
    let c = NSPoint(x: rect.midX, y: rect.minY + rect.height * 0.24)
    NSColor.white.withAlphaComponent(0.9).setStroke()
    let lw = max(1, rect.width * 0.022)
    let circle = NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
    circle.lineWidth = lw; circle.stroke()
    let meridian = NSBezierPath(ovalIn: NSRect(x: c.x - r * 0.45, y: c.y - r, width: r * 0.9, height: 2 * r))
    meridian.lineWidth = lw; meridian.stroke()
    let equator = NSBezierPath(); equator.move(to: NSPoint(x: c.x - r, y: c.y)); equator.line(to: NSPoint(x: c.x + r, y: c.y))
    equator.lineWidth = lw; equator.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: out.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: out.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
