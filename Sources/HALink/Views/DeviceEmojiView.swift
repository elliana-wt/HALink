import AppKit
import CoreText
import SwiftUI

struct DeviceEmojiView: View {
    let value: String
    let fontSize: CGFloat

    var body: some View {
        if let image = EmojiGlyphRenderer.image(value, fontSize: fontSize) {
            Image(nsImage: image)
        }
    }
}

@MainActor
enum EmojiGlyphRenderer {
    private static let cache = NSCache<NSString, NSImage>()

    static func image(_ value: String, fontSize: CGFloat) -> NSImage? {
        let key = "\(fontSize):\(value)" as NSString
        if let image = cache.object(forKey: key) { return image }

        let scale: CGFloat = 4
        let side = ceil(fontSize * 2)
        let pixels = Int(side * scale)
        guard let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
                                      bytesPerRow: pixels * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.scaleBy(x: scale, y: scale)
        let text = NSAttributedString(string: value, attributes: [.font: NSFont.systemFont(ofSize: fontSize)])
        let line = CTLineCreateWithAttributedString(text)
        context.textMatrix = .identity
        let bounds = CTLineGetImageBounds(line, context)
        guard !bounds.isEmpty, !bounds.isNull else { return nil }
        context.textPosition = CGPoint(x: side / 2 - bounds.midX, y: side / 2 - bounds.midY)
        CTLineDraw(line, context)

        // Crop transparent font margins so the shared icon frame centers the visible emoji.
        guard let bytes = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        var left = pixels, right = -1, top = pixels, bottom = -1
        for y in 0..<pixels {
            for x in 0..<pixels where bytes[y * context.bytesPerRow + x * 4 + 3] > 0 {
                left = min(left, x); right = max(right, x)
                top = min(top, y); bottom = max(bottom, y)
            }
        }
        guard right >= left, bottom >= top else { return nil }
        let crop = CGRect(x: left, y: top, width: right - left + 1, height: bottom - top + 1)
        guard let bitmap = context.makeImage()?.cropping(to: crop) else { return nil }
        let image = NSImage(cgImage: bitmap, size: NSSize(width: crop.width / scale, height: crop.height / scale))
        cache.setObject(image, forKey: key, cost: bitmap.bytesPerRow * bitmap.height)
        cache.totalCostLimit = 4 * 1024 * 1024
        return image
    }
}
