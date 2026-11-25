import Foundation

public enum HAControl: Equatable, Sendable {
    case brightness(Double), colorTemperature(Double), color(hue: Double, saturation: Double)
    case coverPosition(Double)
    case temperature(Double), temperatureRange(low: Double, high: Double)
    case temperatureLow(Double), temperatureHigh(Double)
    case hvacMode(String), fanMode(String), swingMode(String), horizontalSwingMode(String), preset(String)

    /// Replace an unsent value for the same control, while keeping different controls in order.
    public var key: String {
        switch self {
        case .brightness: "brightness"
        case .colorTemperature, .color: "lightColor"
        case .coverPosition: "coverPosition"
        case .temperature, .temperatureRange: "temperature"
        case .temperatureLow: "temperatureLow"
        case .temperatureHigh: "temperatureHigh"
        case .hvacMode: "hvacMode"
        case .fanMode: "fanMode"
        case .swingMode: "swingMode"
        case .horizontalSwingMode: "horizontalSwingMode"
        case .preset: "preset"
        }
    }
}

public enum HAValue: Codable, Equatable, Sendable {
    case string(String), number(Double), bool(Bool), array([HAValue]), object([String: HAValue]), null

    public init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([HAValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: HAValue].self)) }
    }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .number(let n): try c.encode(n)
        case .bool(let b): try c.encode(b)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        case .null: try c.encodeNil()
        }
    }
    public subscript(_ key: String) -> HAValue? {
        guard case .object(let object) = self else { return nil }
        return object[key]
    }
    public var string: String? { if case .string(let s) = self { s } else { nil } }
    public func decoded<T: Decodable>(_ type: T.Type) throws -> T {
        try JSONDecoder().decode(type, from: JSONEncoder().encode(self))
    }
}

public struct HAControlRequest: Equatable, Sendable {
    public let domain: String
    public let service: String
    public let data: [String: HAValue]

    public init(entity: HAEntity, control: HAControl, services: Set<String>) throws {
        guard entity.isAvailable else { throw HAControlError.unavailable }
        let a = entity.attributes
        var values: [String: HAValue] = ["entity_id": .string(entity.id)]
        let service: String
        switch (entity.domain, control) {
        case ("light", .brightness(let value)) where entity.supportsBrightness:
            guard value.isFinite, (0...100).contains(value) else { throw HAControlError.invalidValue }
            service = value == 0 ? "turn_off" : "turn_on"
            if value > 0 { values["brightness_pct"] = .number(value.rounded()) }
        case ("light", .colorTemperature(let value)) where entity.colorTemperatureRange != nil:
            guard let range = entity.colorTemperatureRange, value.isFinite, range.contains(value) else {
                throw HAControlError.invalidValue
            }
            service = "turn_on"; values["color_temp_kelvin"] = .number(value.rounded())
        case ("light", .color(let hue, let saturation)) where entity.supportsColor:
            guard hue.isFinite, saturation.isFinite, (0...360).contains(hue), (0...100).contains(saturation) else {
                throw HAControlError.invalidValue
            }
            service = "turn_on"; values["hs_color"] = .array([.number(hue), .number(saturation)])
        case ("cover", .coverPosition(let value)) where entity.supportsCoverPosition:
            guard value.isFinite, (0...100).contains(value) else { throw HAControlError.invalidValue }
            service = "set_cover_position"; values["position"] = .number(value.rounded())
        case ("climate", .temperature(let value)) where entity.supportsTargetTemperature:
            guard let range = entity.temperatureRange, value.isFinite, range.contains(value) else {
                throw HAControlError.invalidValue
            }
            service = "set_temperature"; values["temperature"] = .number(entity.snappedTemperature(value))
        case ("climate", .temperatureRange(let low, let high)) where entity.supportsTargetRange:
            guard let range = entity.temperatureRange, low.isFinite, high.isFinite,
                  range.contains(low), range.contains(high), low <= high else { throw HAControlError.invalidValue }
            service = "set_temperature"
            values["target_temp_low"] = .number(entity.snappedTemperature(low))
            values["target_temp_high"] = .number(entity.snappedTemperature(high))
        case ("climate", .temperatureLow(let low)) where entity.supportsTargetRange:
            guard let high = a.targetTempHigh else { throw HAControlError.invalidValue }
            self = try Self(entity: entity, control: .temperatureRange(low: min(low, high), high: high), services: services)
            return
        case ("climate", .temperatureHigh(let high)) where entity.supportsTargetRange:
            guard let low = a.targetTempLow else { throw HAControlError.invalidValue }
            self = try Self(entity: entity, control: .temperatureRange(low: low, high: max(low, high)), services: services)
            return
        case ("climate", .hvacMode(let mode)) where a.hvacModes?.contains(mode) == true:
            service = "set_hvac_mode"; values["hvac_mode"] = .string(mode)
        case ("climate", .fanMode(let mode)) where entity.hasFeature(8) && a.fanModes?.contains(mode) == true:
            service = "set_fan_mode"; values["fan_mode"] = .string(mode)
        case ("climate", .swingMode(let mode)) where entity.hasFeature(32) && a.swingModes?.contains(mode) == true:
            service = "set_swing_mode"; values["swing_mode"] = .string(mode)
        case ("climate", .horizontalSwingMode(let mode)) where entity.hasFeature(512) && a.swingHorizontalModes?.contains(mode) == true:
            service = "set_swing_horizontal_mode"; values["swing_horizontal_mode"] = .string(mode)
        case ("climate", .preset(let mode)) where entity.hasFeature(16) && a.presetModes?.contains(mode) == true:
            service = "set_preset_mode"; values["preset_mode"] = .string(mode)
        default: throw HAControlError.unsupported
        }
        guard services.contains("\(entity.domain).\(service)") else { throw HAControlError.unsupported }
        self.domain = entity.domain; self.service = service; self.data = values
    }

    public func isConfirmed(by entity: HAEntity) -> Bool {
        guard entity.id == data["entity_id"]?.string, entity.isAvailable else { return false }
        let a = entity.attributes
        if service == "turn_off" { return entity.powerState == false }
        if case .number(let percent) = data["brightness_pct"] {
            guard let actual = entity.brightnessPercent, abs(actual - percent) <= 1 else { return false }
        }
        if case .number(let position) = data["position"] {
            if entity.state == "opening" || entity.state == "closing" { return true }
            guard let actual = entity.coverPositionPercent, abs(actual - position) <= 2 else { return false }
        }
        if case .number(let kelvin) = data["color_temp_kelvin"] {
            guard let actual = entity.colorTemperature, abs(actual - kelvin) <= 75, a.colorMode == "color_temp" else { return false }
        }
        if case .array(let hs) = data["hs_color"], hs.count == 2,
           case .number(let hue) = hs[0], case .number(let saturation) = hs[1] {
            guard let actual = a.hsColor, actual.count >= 2, a.colorMode != "color_temp" else { return false }
            let difference = abs(actual[0] - hue).truncatingRemainder(dividingBy: 360)
            guard (saturation < 1 || min(difference, 360 - difference) <= 3), abs(actual[1] - saturation) <= 3 else { return false }
        }
        for (key, actual) in [("temperature", a.temperature), ("target_temp_low", a.targetTempLow), ("target_temp_high", a.targetTempHigh)] {
            if case .number(let wanted) = data[key] {
                guard let actual, abs(actual - wanted) < 0.05 else { return false }
            }
        }
        for (key, actual) in [("hvac_mode", Optional(entity.state)), ("fan_mode", a.fanMode), ("swing_mode", a.swingMode),
                              ("swing_horizontal_mode", a.swingHorizontalMode), ("preset_mode", a.presetMode)] {
            if let wanted = data[key]?.string, actual != wanted { return false }
        }
        return domain != "light" || entity.powerState == true
    }
}

public enum HAControlError: LocalizedError {
    case unavailable, unsupported, invalidValue
    public var errorDescription: String? {
        switch self {
        case .unavailable: "设备当前不可用，请检查设备连接。"
        case .unsupported: "这个设备当前不支持此操作，请刷新设备状态。"
        case .invalidValue: "参数超出设备支持的范围，请重新调整。"
        }
    }
}

extension HAEntity {
    public func hasFeature(_ bit: Int) -> Bool { (attributes.supportedFeatures ?? 0) & bit != 0 }
    public var supportsBrightness: Bool {
        domain == "light" && !(Set(attributes.supportedColorModes ?? [])
            .intersection(["brightness", "color_temp", "hs", "xy", "rgb", "rgbw", "rgbww", "white"]).isEmpty)
    }
    public var supportsColor: Bool {
        domain == "light" && !Set(attributes.supportedColorModes ?? []).intersection(["hs", "xy", "rgb", "rgbw", "rgbww"]).isEmpty
    }
    public var brightnessPercent: Double? {
        guard supportsBrightness else { return nil }
        if powerState == false { return 0 }
        return attributes.brightness.map { max(0, min(100, $0 / 255 * 100)) }
    }
    public var supportsCoverPosition: Bool {
        domain == "cover" && hasFeature(4)
    }
    public var coverPositionPercent: Double? {
        guard domain == "cover" else { return nil }
        if let position = attributes.currentPosition {
            return max(0, min(100, position))
        }
        if state == "open" { return 100 }
        if state == "closed" { return 0 }
        return nil
    }
    public var colorTemperatureRange: ClosedRange<Double>? {
        guard domain == "light", attributes.supportedColorModes?.contains("color_temp") == true else { return nil }
        let low = attributes.minColorTempKelvin ?? attributes.maxMireds.flatMap { $0 > 0 ? 1_000_000 / $0 : nil }
        let high = attributes.maxColorTempKelvin ?? attributes.minMireds.flatMap { $0 > 0 ? 1_000_000 / $0 : nil }
        guard let low, let high, low.isFinite, high.isFinite, low > 0, high > low else { return nil }
        return low...high
    }
    public var colorTemperature: Double? {
        attributes.colorTempKelvin ?? attributes.colorTemp.flatMap { $0 > 0 ? 1_000_000 / $0 : nil }
    }
    public var temperatureRange: ClosedRange<Double>? {
        guard domain == "climate", let low = attributes.minTemp, let high = attributes.maxTemp,
              low.isFinite, high.isFinite, high > low else { return nil }
        return low...high
    }
    public var temperatureStep: Double {
        guard let step = attributes.targetTempStep, step.isFinite, step > 0 else { return 1 }
        return step
    }
    public func snappedTemperature(_ value: Double) -> Double {
        guard let range = temperatureRange else { return value }
        let snapped = range.lowerBound + ((value - range.lowerBound) / temperatureStep).rounded() * temperatureStep
        return max(range.lowerBound, min(range.upperBound, (snapped * 1000).rounded() / 1000))
    }
    public var supportsTargetRange: Bool {
        domain == "climate" && hasFeature(2) && (state == "heat_cool" || !hasFeature(1))
    }
    public var supportsTargetTemperature: Bool {
        domain == "climate" && hasFeature(1) && !supportsTargetRange
    }
}
