// Draws the DMG window background: a short instruction and an arrow from the
// app icon to the Applications folder. It writes a 1x and a 2x PNG.
// Usage: swift make_dmg_background.swift <output-folder>
//
// The positions here must agree with the icon positions in scripts/dmg_settings.py.
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

// Window content size in points. Finder measures y from the top; AppKit from the bottom.
let width: CGFloat = 600
let height: CGFloat = 440
let iconY: CGFloat = 150  // Finder y of the icon centres (dmg_settings.py)
let appX: CGFloat = 150
let applicationsX: CGFloat = 450

let green = NSColor(srgbRed: 0.0, green: 0.52, blue: 0.44, alpha: 1)

func render(scale: CGFloat) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: width, height: height)  // 72 dpi at 1x, 144 dpi at 2x
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let bounds = NSRect(x: 0, y: 0, width: width, height: height)
    NSGradient(starting: NSColor(srgbRed: 0.97, green: 0.98, blue: 0.97, alpha: 1),
               ending: NSColor(srgbRed: 0.90, green: 0.93, blue: 0.92, alpha: 1))!.draw(in: bounds, angle: -90)

    // Instruction at the top.
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let title = NSAttributedString(string: "Drag PAYE Launcher to Applications", attributes: [
        .font: NSFont.systemFont(ofSize: 18, weight: .semibold),
        .foregroundColor: NSColor(srgbRed: 0.15, green: 0.2, blue: 0.19, alpha: 1),
        .paragraphStyle: paragraph,
    ])
    title.draw(in: NSRect(x: 0, y: height - 62, width: width, height: 28))

    // Arrow between the two icons (the icons are 112 points wide).
    let y = height - iconY
    let start = NSPoint(x: appX + 88, y: y)
    let tip = NSPoint(x: applicationsX - 88, y: y)
    let head: CGFloat = 22
    green.setStroke()
    green.setFill()
    let shaft = NSBezierPath()
    shaft.move(to: start)
    shaft.curve(to: NSPoint(x: tip.x - head * 0.8, y: y),
                controlPoint1: NSPoint(x: start.x + 40, y: y + 26),
                controlPoint2: NSPoint(x: tip.x - 50, y: y + 26))
    shaft.lineWidth = 7
    shaft.lineCapStyle = .round
    shaft.stroke()
    let arrowHead = NSBezierPath()
    arrowHead.move(to: tip)
    arrowHead.line(to: NSPoint(x: tip.x - head, y: y + head * 0.7))
    arrowHead.line(to: NSPoint(x: tip.x - head, y: y - head * 0.7))
    arrowHead.close()
    arrowHead.fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

try render(scale: 1).write(to: out.appendingPathComponent("background.png"))
try render(scale: 2).write(to: out.appendingPathComponent("background@2x.png"))
