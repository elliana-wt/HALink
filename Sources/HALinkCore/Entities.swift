import Foundation

public struct HAEntity: Codable, Identifiable, Equatable, Sendable {
    public struct Attributes: Codable, Equatable, Sendable {
        public var friendlyName: String?
        public var supportedFeatures: Int?
        public var brightness: Double?
        public var currentPosition: Double?
        public var supportedColorModes: [String]?
        public var colorMode: String?
        public var colorTempKelvin: Double?
        public var minColorTempKelvin: Double?
        public var maxColorTempKelvin: Double?
        public var colorTemp: Double?
        public var minMireds: Double?
        public var maxMireds: Double?
        public var hsColor: [Double]?
        public var rgbColor: [Double]?
        public var temperature: Double?
        public var currentTemperature: Double?
        public var targetTempLow: Double?
        public var targetTempHigh: Double?
        public var minTemp: Double?
        public var maxTemp: Double?
        public var targetTempStep: Double?
        public var hvacModes: [String]?
        public var hvacAction: String?
        public var fanMode: String?
        public var fanModes: [String]?
        public var swingMode: String?
        public var swingModes: [String]?
        public var swingHorizontalMode: String?
        public var swingHorizontalModes: [String]?
        public var presetMode: String?
        public var presetModes: [String]?
        enum CodingKeys: String, CodingKey {
            case friendlyName = "friendly_name", supportedFeatures = "supported_features"
            case brightness, currentPosition = "current_position", temperature
            case supportedColorModes = "supported_color_modes", colorMode = "color_mode"
            case colorTempKelvin = "color_temp_kelvin", minColorTempKelvin = "min_color_temp_kelvin"
            case maxColorTempKelvin = "max_color_temp_kelvin", colorTemp = "color_temp"
            case minMireds = "min_mireds", maxMireds = "max_mireds"
            case hsColor = "hs_color", rgbColor = "rgb_color"
            case currentTemperature = "current_temperature", targetTempLow = "target_temp_low"
            case targetTempHigh = "target_temp_high", minTemp = "min_temp", maxTemp = "max_temp"
            case targetTempStep = "target_temp_step", hvacModes = "hvac_modes", hvacAction = "hvac_action"
            case fanMode = "fan_mode", fanModes = "fan_modes", swingMode = "swing_mode", swingModes = "swing_modes"
            case swingHorizontalMode = "swing_horizontal_mode", swingHorizontalModes = "swing_horizontal_modes"
            case presetMode = "preset_mode", presetModes = "preset_modes"
        }
        public init(friendlyName: String? = nil, supportedFeatures: Int? = nil) {
            self.friendlyName = friendlyName
            self.supportedFeatures = supportedFeatures
        }
    }
    public var entityID: String
    public var state: String
    public var attributes: Attributes
    public var lastUpdated: String?
    public var id: String { entityID }
    public var domain: String { String(entityID.split(separator: ".").first ?? "") }
    public var name: String { attributes.friendlyName ?? entityID }
    public var isAvailable: Bool {
        state != "unavailable" && (state != "unknown" || ["scene", "button", "input_button"].contains(domain))
    }
    public var powerState: Bool? {
        guard isAvailable else { return nil }
        switch domain {
        case "light", "switch", "fan", "input_boolean":
            return state == "on" ? true : state == "off" ? false : nil
        case "climate":
            if state == "off" { return false }
            return ["heat", "cool", "heat_cool", "auto", "dry", "fan_only"].contains(state) ? true : nil
        case "media_player":
            if state == "off" { return false }
            return ["on", "idle", "playing", "paused", "buffering"].contains(state) ? true : nil
        default: return nil
        }
    }
    public var icon: String {
        switch domain {
        case "light": "lightbulb"
        case "switch", "input_boolean": "powerplug"
        case "fan": "fan"
        case "cover": "blinds.horizontal.closed"
        case "climate": "thermometer.medium"
        case "media_player": "hifispeaker"
        case "scene": "sparkles"
        case "script": "play.square"
        default: "button.programmable"
        }
    }
    public var stateLabel: String {
        switch state {
        case "on": "已开启"
        case "off": "已关闭"
        case "unavailable": "不可用"
        case "unknown": ["scene", "button", "input_button"].contains(domain) ? "可执行" : "状态未知"
        case "open": "已打开"
        case "closed": "已关闭"
        case "opening": "正在打开"
        case "closing": "正在关闭"
        case "playing": "播放中"
        case "paused": "已暂停"
        case "idle": "待机"
        default: ["scene", "script", "button", "input_button"].contains(domain) ? "可执行" : state
        }
    }
    enum CodingKeys: String, CodingKey { case entityID = "entity_id", state, attributes, lastUpdated = "last_updated" }
    public init(entityID: String, state: String, attributes: Attributes = .init()) {
        self.entityID = entityID; self.state = state; self.attributes = attributes
    }
}

public enum DeviceAction: String, Codable, CaseIterable, Identifiable, Sendable {
    case toggle, turnOn = "turn_on", turnOff = "turn_off"
    case open = "open_cover", close = "close_cover", stop = "stop_cover"
    case playPause = "media_play_pause", next = "media_next_track", previous = "media_previous_track"
    case press
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .toggle: "切换开关"
        case .turnOn: "开启 / 执行"
        case .turnOff: "关闭"
        case .open: "打开"
        case .close: "关闭"
        case .stop: "停止"
        case .playPause: "播放 / 暂停"
        case .next: "下一曲"
        case .previous: "上一曲"
        case .press: "按下按钮"
        }
    }
    public static func candidates(for domain: String) -> [Self] {
        switch domain {
        case "light", "switch", "fan", "input_boolean": [.toggle, .turnOn, .turnOff]
        case "cover": [.open, .close, .stop]
        case "climate": [.turnOn, .turnOff]
        case "media_player": [.playPause, .turnOn, .turnOff, .next, .previous]
        case "scene", "script": [.turnOn]
        case "button", "input_button": [.press]
        default: []
        }
    }
    public static func available(for entity: HAEntity, services: Set<String>) -> [Self] {
        candidates(for: entity.domain).filter { action in
            if entity.domain == "climate", action == .turnOn || action == .turnOff {
                let bit = action == .turnOn ? 256 : 128
                if entity.hasFeature(bit), services.contains("climate.\(action.rawValue)") { return true }
                guard services.contains("climate.set_hvac_mode"), let modes = entity.attributes.hvacModes else { return false }
                return action == .turnOff ? modes.contains("off") : modes.contains(where: { $0 != "off" })
            }
            guard services.contains("\(entity.domain).\(action.rawValue)") else { return false }
            let flags = entity.attributes.supportedFeatures ?? 0
            if entity.domain == "cover" {
                let bit = action == .open ? 1 : action == .close ? 2 : 8
                return flags & bit != 0
            }
            if entity.domain == "media_player", action == .turnOn || action == .turnOff {
                return flags & (action == .turnOn ? 128 : 256) != 0
            }
            return true
        }
    }
}

public struct DeviceBinding: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var entityID: String
    public var name: String
    public var action: DeviceAction
    public var shortcut: HotKey?
    public var icon: DeviceIcon?
    public var iconColor: DeviceIconColor?
    public init(id: UUID = UUID(), entityID: String, name: String, action: DeviceAction,
                shortcut: HotKey? = nil, icon: DeviceIcon? = nil, iconColor: DeviceIconColor? = nil) {
        self.id = id; self.entityID = entityID; self.name = name; self.action = action
        self.shortcut = shortcut
        self.icon = icon
        self.iconColor = iconColor
    }
}
