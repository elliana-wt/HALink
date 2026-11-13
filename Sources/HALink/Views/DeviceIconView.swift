import AppKit
import HALinkCore
import SwiftUI

struct DeviceIconView: View {
    let icon: DeviceIcon?
    let fallback: String
    var color: DeviceIconColor?
    var isActive = true
    var size: CGFloat = 21

    var body: some View {
        Group {
            if case .emoji(let value) = icon, icon?.isValid == true {
                DeviceEmojiView(value: value, fontSize: size)
            } else {
                Image(systemName: symbol)
                    .font(.system(size: size, weight: .medium))
                    .foregroundStyle(color?.swiftUIColor ?? (isActive ? Color.teal : Color.secondary))
            }
        }
        .frame(width: size * 1.5, height: size * 1.5, alignment: .center)
        .accessibilityHidden(true)
    }

    private var symbol: String {
        if case .symbol(let name) = icon, !name.isEmpty { return name }
        return fallback
    }
}

struct DeviceIconTile: View {
    let icon: DeviceIcon?
    let fallback: String
    var color: DeviceIconColor?
    var isActive = true

    var body: some View {
        DeviceIconView(icon: icon, fallback: fallback, color: color, isActive: isActive)
            .frame(width: 42, height: 42)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 11))
    }
}

extension DeviceIconColor {
    var swiftUIColor: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: 1)
    }

    init?(color: Color) {
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        self.init(red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent)
    }
}
