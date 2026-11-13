import Foundation

public struct DeviceIconColor: Codable, Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

public enum DeviceIcon: Codable, Equatable, Sendable {
    case symbol(String)
    case emoji(String)

    public var isValid: Bool {
        switch self {
        case .symbol(let name):
            !name.isEmpty
        case .emoji(let value):
            value.count == 1 && value.unicodeScalars.contains {
                $0.properties.isEmojiPresentation || ($0.properties.isEmoji && value.unicodeScalars.count > 1)
            }
        }
    }
}
