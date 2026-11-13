import Foundation
import Carbon

public struct HotKey: Codable, Equatable, Hashable, Sendable {
    public let keyCode: UInt32
    public let modifiers: UInt32
    public let label: String
    public static let functionKeys: [UInt32: String] = [
        122:"F1",120:"F2",99:"F3",118:"F4",96:"F5",97:"F6",98:"F7",100:"F8",101:"F9",109:"F10",
        103:"F11",111:"F12",105:"F13",107:"F14",113:"F15",106:"F16",64:"F17",79:"F18",80:"F19",90:"F20"
    ]
    public init(keyCode: UInt32, modifiers: UInt32, label: String) {
        self.keyCode = keyCode
        // Fn/caps lock are not part of the shortcut, including on F13–F20 keyboards.
        self.modifiers = modifiers & UInt32(cmdKey | controlKey | optionKey | shiftKey)
        self.label = Self.functionKeys[keyCode] ?? label
    }
    public var isValid: Bool {
        guard keyCode < 128, !label.isEmpty, modifiers & ~UInt32(cmdKey | controlKey | optionKey | shiftKey) == 0,
              ![54,55,56,57,58,59,60,61,62,63,72,73,74].contains(keyCode) else { return false }
        return Self.functionKeys[keyCode] != nil || modifiers & UInt32(cmdKey | controlKey | optionKey) != 0
    }
    public func matches(_ other: Self) -> Bool { keyCode == other.keyCode && modifiers == other.modifiers }
    public var displayName: String {
        var text = ""
        for (mask, symbol) in [(controlKey,"⌃"),(optionKey,"⌥"),(shiftKey,"⇧"),(cmdKey,"⌘")] {
            if modifiers & UInt32(mask) != 0 { text += symbol }
        }
        return text + label
    }
}
