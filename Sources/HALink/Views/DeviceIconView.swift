import AppKit
import HALinkCore
import SwiftUI

struct DeviceIconView: View {
    let icon: DeviceIcon?
    let fallback: String
    var color: DeviceIconColor?
    var tintOverride: Color? = nil
    var isActive = true
    var size: CGFloat = 21
    @Environment(\.homePhotoTheme) private var homePhotoTheme

    var body: some View {
        Group {
            if case .emoji(let value) = icon, icon?.isValid == true {
                DeviceEmojiView(value: value, fontSize: size)
            } else {
                Image(systemName: symbol)
                    .font(.system(size: size, weight: .medium))
                    .foregroundStyle(resolvedColor)
            }
        }
        .frame(width: size * 1.5, height: size * 1.5, alignment: .center)
        .accessibilityHidden(true)
    }

    private var resolvedColor: Color {
        if let tintOverride { return tintOverride }
        if let homePhotoTheme {
            return isActive ? homePhotoTheme.accentColor : .secondary
        }
        if let color { return color.swiftUIColor }
        return isActive ? .orange : .secondary
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
    var tintOverride: Color? = nil
    var isActive = true
    @Environment(\.homePhotoTheme) private var homePhotoTheme

    var body: some View {
        DeviceIconView(icon: icon, fallback: fallback, color: color, tintOverride: tintOverride, isActive: isActive)
            .frame(width: 42, height: 42)
            .background {
                if let theme = homePhotoTheme {
                    RoundedRectangle(cornerRadius: 11)
                        .fill(theme.surfaceColor.opacity(0.45))
                        .overlay {
                            RoundedRectangle(cornerRadius: 11)
                                .fill(theme.color.opacity(0.18))
                        }
                } else {
                    RoundedRectangle(cornerRadius: 11)
                        .fill(.quaternary.opacity(0.5))
                }
            }
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
