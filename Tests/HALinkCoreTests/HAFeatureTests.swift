import Foundation
import HALinkCore
import Testing

@Suite("灯光、空调和实时状态")
struct HAFeatureTests {
    private func entity(_ json: String) throws -> HAEntity {
        try JSONDecoder().decode(HAEntity.self, from: Data(json.utf8))
    }
    @Test func lightCapabilitiesAndZeroBrightness() throws {
        let light = try entity(#"{"entity_id":"light.a","state":"on","attributes":{"supported_color_modes":["color_temp","rgb"],"brightness":128,"min_color_temp_kelvin":2700,"max_color_temp_kelvin":6500}}"#)
        #expect(light.supportsBrightness && light.supportsColor)
        #expect(light.colorTemperatureRange == 2700...6500)
        let off = try HAControlRequest(entity: light, control: .brightness(0), services: ["light.turn_off"])
        #expect(off.service == "turn_off")
        #expect(off.data["brightness_pct"] == nil)
        #expect(throws: HAControlError.self) {
            try HAControlRequest(entity: light, control: .colorTemperature(2000), services: ["light.turn_on"])
        }
        let binary = try entity(#"{"entity_id":"light.a","state":"off","attributes":{"supported_color_modes":["onoff"]}}"#)
        #expect(!binary.supportsBrightness && !binary.supportsColor)
        #expect(throws: HAControlError.self) {
            try HAControlRequest(entity: binary, control: .brightness(50), services: ["light.turn_on"])
        }
    }
    @Test func legacyMiredsAndNullableAttributes() throws {
        let light = try entity(#"{"entity_id":"light.a","state":"off","attributes":{"supported_color_modes":["color_temp"],"brightness":null,"color_temp":250,"min_mireds":200,"max_mireds":500}}"#)
        #expect(light.colorTemperatureRange == 2000...5000)
        #expect(light.colorTemperature == 4000)
        #expect(light.brightnessPercent == 0)
    }
    @Test func coverPositionControlAndConfirmation() throws {
        let cover = try entity(#"{"entity_id":"cover.curtain","state":"open","attributes":{"supported_features":15,"current_position":80}}"#)
        #expect(cover.supportsCoverPosition)
        #expect(cover.coverPositionPercent == 80)
        let command = try HAControlRequest(entity: cover, control: .coverPosition(45.4), services: ["cover.set_cover_position"])
        #expect(command.domain == "cover")
        #expect(command.service == "set_cover_position")
        #expect(command.data["position"] == .number(45))
        let moving = try entity(#"{"entity_id":"cover.curtain","state":"closing","attributes":{"supported_features":15,"current_position":72}}"#)
        #expect(command.isConfirmed(by: moving))
        let settled = try entity(#"{"entity_id":"cover.curtain","state":"open","attributes":{"supported_features":15,"current_position":45}}"#)
        #expect(command.isConfirmed(by: settled))
        let fixed = try entity(#"{"entity_id":"cover.garage","state":"closed","attributes":{"supported_features":3}}"#)
        #expect(!fixed.supportsCoverPosition)
        #expect(fixed.coverPositionPercent == 0)
        #expect(throws: HAControlError.self) {
            try HAControlRequest(entity: fixed, control: .coverPosition(50), services: ["cover.set_cover_position"])
        }
    }
    @Test func climateUnitsAndHalfDegreeStep() throws {
        let climate = try entity(#"{"entity_id":"climate.a","state":"heat","attributes":{"supported_features":1,"min_temp":60,"max_temp":86,"target_temp_step":0.5,"temperature":70.5}}"#)
        #expect(climate.supportsTargetTemperature)
        #expect(climate.temperatureRange == 60...86)
        let command = try HAControlRequest(entity: climate, control: .temperature(70.7), services: ["climate.set_temperature"])
        #expect(command.data["temperature"] == .number(70.5))
        #expect(command.isConfirmed(by: climate))
        #expect(throws: HAControlError.self) {
            try HAControlRequest(entity: climate, control: .temperature(90), services: ["climate.set_temperature"])
        }
    }
    @Test func rangeControlsPreserveOtherBoundAtExecutionTime() throws {
        let climate = try entity(#"{"entity_id":"climate.a","state":"heat_cool","attributes":{"supported_features":3,"min_temp":16,"max_temp":30,"target_temp_step":0.5,"target_temp_low":20,"target_temp_high":26}}"#)
        #expect(climate.supportsTargetRange && !climate.supportsTargetTemperature)
        let low = try HAControlRequest(entity: climate, control: .temperatureLow(22), services: ["climate.set_temperature"])
        #expect(low.data["target_temp_low"] == .number(22))
        #expect(low.data["target_temp_high"] == .number(26))
        #expect(throws: HAControlError.self) {
            try HAControlRequest(entity: climate, control: .temperature(25), services: ["climate.set_temperature"])
        }
        #expect(throws: HAControlError.self) {
            try HAControlRequest(entity: climate, control: .temperatureRange(low: 27, high: 21), services: ["climate.set_temperature"])
        }
    }
    @Test func modesAndPresetsAreDeviceSpecific() throws {
        let climate = try entity(#"{"entity_id":"climate.a","state":"heat","attributes":{"supported_features":56,"hvac_modes":["off","heat"],"fan_modes":["quiet","turbo"],"swing_modes":["off","vertical"],"preset_modes":["none","eco"]}}"#)
        let fan = try HAControlRequest(entity: climate, control: .fanMode("quiet"), services: ["climate.set_fan_mode"])
        #expect(fan.data["fan_mode"] == .string("quiet"))
        #expect(throws: HAControlError.self) {
            try HAControlRequest(entity: climate, control: .fanMode("low"), services: ["climate.set_fan_mode"])
        }
        #expect(throws: HAControlError.self) {
            try HAControlRequest(entity: climate, control: .preset("sleep"), services: ["climate.set_preset_mode"])
        }
        #expect(throws: HAControlError.self) {
            try HAControlRequest(entity: climate, control: .preset("eco"), services: [])
        }
        #expect(DeviceAction.available(for: climate, services: ["climate.set_hvac_mode"]) == [.turnOn, .turnOff])
    }
    @Test func eventRemovalAndSnapshotRace() throws {
        let older = try entity(#"{"entity_id":"light.a","state":"off","attributes":{},"last_updated":"2026-11-24T12:00:00.100Z"}"#)
        let newer = try entity(#"{"entity_id":"light.a","state":"on","attributes":{},"last_updated":"2026-11-24T12:00:00.200Z"}"#)
        let message = try JSONDecoder().decode(HAWebSocketMessage.self, from: Data(#"{"type":"event","event":{"event_type":"state_changed","data":{"entity_id":"light.a","new_state":{"entity_id":"light.a","state":"off","attributes":{},"last_updated":"2026-11-24T12:00:00.100Z"}}}}"#.utf8))
        let change = try #require(try message.stateChange())
        #expect(HASnapshot.merging([newer], changes: [change]) == [newer])
        #expect(HASnapshot.merging([older], changes: [change]).first?.state == "off")
        let removal = try JSONDecoder().decode(HAWebSocketMessage.self, from: Data(#"{"type":"event","event":{"event_type":"state_changed","time_fired":"2026-11-24T12:00:01Z","data":{"entity_id":"light.a","new_state":null}}}"#.utf8))
        #expect(HASnapshot.merging([newer], changes: [try #require(try removal.stateChange())]).isEmpty)
    }
    @Test func websocketAndDiscoveryAddresses() throws {
        #expect(HARealtime.url(for: try Endpoint("https://ha.example.com")).absoluteString == "wss://ha.example.com/api/websocket")
        #expect(HARealtime.url(for: try Endpoint("http://[::1]:8123")).absoluteString == "ws://[::1]:8123/api/websocket")
        let server = try HADiscoveredServer(name: "HA", host: "ha.local.", port: 8123,
            txt: ["location_name": "家里", "internal_url": "https://home.local:8123"])
        #expect(server.name == "家里" && server.address == "https://home.local:8123")
        let fallback = try HADiscoveredServer(name: "HA", host: "fe80::1%en0", port: 8123,
            txt: ["internal_url": "http://user:password@wrong.local"])
        #expect(fallback.address.contains("fe80::1"))
        #expect(!fallback.address.contains("password"))
    }
}
