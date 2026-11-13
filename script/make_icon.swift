import AppKit
import Foundation

let fm = FileManager.default
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let directory = fm.temporaryDirectory.appendingPathComponent("HALink-\(UUID().uuidString).iconset")
try fm.createDirectory(at: directory, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: directory) }

func roundedPolygon(_ points: [NSPoint], inset: CGFloat) -> NSBezierPath {
    let path = NSBezierPath()
    for i in points.indices {
        let previous = points[(i + points.count - 1) % points.count]
        let vertex = points[i]
        let next = points[(i + 1) % points.count]
        func near(_ point: NSPoint) -> NSPoint {
            let distance = hypot(point.x - vertex.x, point.y - vertex.y)
            return NSPoint(x: vertex.x + (point.x - vertex.x) * inset / distance,
                           y: vertex.y + (point.y - vertex.y) * inset / distance)
        }
        let entry = near(previous)
        let exit = near(next)
        if i == 0 { path.move(to: entry) } else { path.line(to: entry) }
        path.curve(to: exit,
                   controlPoint1: NSPoint(x: entry.x + (vertex.x - entry.x) * 2 / 3,
                                         y: entry.y + (vertex.y - entry.y) * 2 / 3),
                   controlPoint2: NSPoint(x: exit.x + (vertex.x - exit.x) * 2 / 3,
                                         y: exit.y + (vertex.y - exit.y) * 2 / 3))
    }
    path.close()
    return path
}

func draw(_ size: Int) -> Data {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    defer { NSGraphicsContext.restoreGraphicsState() }
    let factor = CGFloat(size) / 1024
    let transform = NSAffineTransform()
    transform.scale(by: factor); transform.concat()
    let shape = NSBezierPath(roundedRect: NSRect(x: 40, y: 40, width: 944, height: 944), xRadius: 214, yRadius: 214)
    let charcoal = NSColor(srgbRed: 0.105, green: 0.11, blue: 0.12, alpha: 1)
    NSGradient(starting: NSColor(srgbRed: 0.16, green: 0.165, blue: 0.18, alpha: 1),
               ending: charcoal)!.draw(in: shape, angle: -90)
    NSColor.white.withAlphaComponent(0.10).setStroke()
    shape.lineWidth = 2
    shape.stroke()

    let house = roundedPolygon([
        NSPoint(x: 512, y: 778), NSPoint(x: 792, y: 550),
        NSPoint(x: 792, y: 258), NSPoint(x: 232, y: 258),
        NSPoint(x: 232, y: 550)
    ], inset: 42)
    NSColor(srgbRed: 0.96, green: 0.965, blue: 0.98, alpha: 1).setFill()
    house.fill()

    NSGraphicsContext.saveGraphicsState()
    let switchTransform = NSAffineTransform()
    switchTransform.translateX(by: 512, yBy: 428)
    switchTransform.scale(by: 0.8)
    switchTransform.translateX(by: -512, yBy: -428)
    switchTransform.concat()
    let track = NSBezierPath(roundedRect: NSRect(x: 312, y: 338, width: 400, height: 180), xRadius: 90, yRadius: 90)
    charcoal.setFill()
    track.fill()

    let thumb = NSBezierPath(roundedRect: NSRect(x: 482, y: 360, width: 208, height: 136), xRadius: 68, yRadius: 68)
    NSColor.white.setFill(); thumb.fill()
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}
for size in [16, 32, 128, 256, 512] {
    try draw(size).write(to: directory.appendingPathComponent("icon_\(size)x\(size).png"))
    try draw(size * 2).write(to: directory.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", directory.path, "-o", root.appendingPathComponent("Resources/AppIcon.icns").path]
try process.run(); process.waitUntilExit()
guard process.terminationStatus == 0 else { exit(process.terminationStatus) }
