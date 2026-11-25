import Foundation
import HALinkCore
import Testing
@testable import HALink

@Suite("模拟 HA：实时连接与控制指令", .serialized)
struct AppModelTests {
    @Test func realtimeMetadataExternalChangesAndReconnect() async throws {
        let fixture = try MockHA()
        defer { fixture.stop() }
        let model = try fixture.model()
        defer { model.stop() }
        await model.start()
        try await waitFor { model.realtimeStatus == .live && model.homeMetadata.temperatureUnit == "°C" && model.areaName(for: "light.desk") == "书房" }
        #expect(model.areaName(for: "climate.living") == "客厅")
        try await fixture.post("change", ["entity_id": .string("light.desk"), "state": .string("off")])
        try await waitFor { model.entities["light.desk"]?.powerState == false }
        try await fixture.post("change", ["entity_id": .string("light.ceiling"), "remove": .bool(true)])
        try await waitFor { model.entities["light.ceiling"] == nil }
        try await fixture.post("drop")
        try await waitFor { model.realtimeStatus != .live }
        try await waitFor { model.realtimeStatus == .live }
        #expect(model.entities["light.desk"]?.state == "off")
        model.disconnect()
        try await fixture.post("change", ["entity_id": .string("light.desk"), "state": .string("on")])
        try await Task.sleep(for: .milliseconds(100))
        #expect(model.entities.isEmpty)
        #expect(model.realtimeStatus == .stopped)
    }

    @Test func sliderCoalescingAndDifferentControlsArePreserved() async throws {
        let fixture = try MockHA()
        defer { fixture.stop() }
        let model = try fixture.model()
        defer { model.stop() }
        await model.start()
        try await waitFor { model.realtimeStatus == .live }
        let light = try #require(model.devices.first { $0.entityID == "light.desk" })
        let climate = try #require(model.devices.first { $0.entityID == "climate.living" })
        for brightness in 20...80 { model.setControl(light.id, .brightness(Double(brightness))) }
        model.setControl(light.id, .colorTemperature(3700))
        model.setControl(climate.id, .temperature(24.5))
        model.setControl(climate.id, .fanMode("low"))
        model.setControl(climate.id, .preset("eco"))
        try await waitFor {
            model.entities["light.desk"]?.attributes.colorTempKelvin == 3700 &&
            model.entities["climate.living"]?.attributes.presetMode == "eco" && model.busyIDs.isEmpty
        }
        #expect(abs((model.entities["light.desk"]?.brightnessPercent ?? 0) - 80) < 1)
        #expect(model.entities["climate.living"]?.attributes.temperature == 24.5)
        #expect(model.entities["climate.living"]?.attributes.fanMode == "low")
        #expect(model.actionErrors.isEmpty)
        let counters = try await fixture.get("counters")
        let commands = try #require(try counters["commands"]?.decoded([[String: HAValue]].self))
        #expect(commands.filter { $0["data"]?["brightness_pct"] != nil }.count == 1)
        #expect(commands.count == 5)
    }

    @Test func unsupportedCommandDoesNotReachDeviceAndInvalidTokenDoesNotLoop() async throws {
        let fixture = try MockHA()
        defer { fixture.stop() }
        let model = try fixture.model()
        defer { model.stop() }
        await model.start()
        try await waitFor { model.realtimeStatus == .live }
        let climate = try #require(model.devices.first { $0.entityID == "climate.living" })
        model.setControl(climate.id, .preset("unsupported-preset"))
        try await waitFor { model.actionErrors[climate.id] != nil && model.busyIDs.isEmpty }
        #expect(try await fixture.get("counters")["commands"]?.decoded([HAValue].self).isEmpty == true)
        let denied = HARealtime(endpoint: try Endpoint(fixture.address), token: "invalid")
        var status: HARealtime.Status = .stopped
        denied.onStatus = { status = $0 }
        denied.start()
        defer { denied.stop() }
        try await waitFor { status == .unauthorized }
        try await Task.sleep(for: .milliseconds(150))
        #expect(status == .unauthorized)
    }

    @Test func discoversPublishedHAWithoutConnectingOrSavingCredentials() async throws {
        let fixture = try MockHA()
        defer { fixture.stop() }
        let name = "HALink Fixture \(UUID().uuidString.prefix(8))"
        let service = NetService(domain: "local.", type: "_home-assistant._tcp.", name: name, port: 8123)
        service.setTXTRecord(NetService.data(fromTXTRecord: ["location_name": Data(name.utf8), "internal_url": Data(fixture.address.utf8)]))
        service.publish()
        defer { service.stop() }
        let discovery = HADiscovery()
        discovery.start()
        defer { discovery.stop() }
        try await waitFor { discovery.servers.contains { $0.name == name && $0.address == fixture.address } }
        #expect(discovery.searching)
        #expect(try await fixture.get("counters")["connections"] == .number(0))
    }

    @Test func olderHTTPRefreshDoesNotOverwriteNewerRealtimeState() async throws {
        let fixture = try MockHA()
        defer { fixture.stop() }
        let model = try fixture.model()
        defer { model.stop() }
        await model.start()
        try await waitFor { model.realtimeStatus == .live }
        #expect(model.entities["light.desk"]?.powerState == true)
        try await fixture.post("stale-snapshot")
        await model.refresh()
        #expect(model.entities["light.desk"]?.powerState == false)
        #expect(model.isConnected)
    }

    private func waitFor(_ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(6)
        while !predicate() {
            guard ContinuousClock.now < deadline else { Issue.record("等待模拟 HA 状态超时"); throw HAError.invalidResponse }
            try await Task.sleep(for: .milliseconds(25))
        }
    }
}

private final class MockHA {
    let process = Process()
    let address: String
    init() throws {
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appending(path: "../HALinkCoreTests/Fixtures/mock_ha.py").standardizedFileURL.path]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.environment = ProcessInfo.processInfo.environment.merging(["PYTHONDONTWRITEBYTECODE": "1"]) { _, new in new }
        try process.run()
        let port = String(decoding: output.fileHandleForReading.availableData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let number = Int(port), (1...65535).contains(number) else {
            if process.isRunning { process.terminate() }
            throw HAError.invalidResponse
        }
        address = "http://127.0.0.1:\(number)"
    }
    func stop() { if process.isRunning { process.terminate(); process.waitUntilExit() } }
    func model() throws -> AppModel {
        var config = Configuration(address: address)
        config.devices = [DeviceBinding(entityID: "light.desk", name: "台灯", action: .toggle),
                          DeviceBinding(entityID: "climate.living", name: "空调", action: .turnOn)]
        return AppModel(configuration: config, client: try HAClient(endpoint: Endpoint(address), token: "fixture-token"))
    }
    func post(_ path: String, _ value: [String: HAValue] = [:]) async throws {
        var request = URLRequest(url: URL(string: address + "/test/" + path)!)
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(value)
        _ = try await URLSession.shared.data(for: request)
    }
    func get(_ path: String) async throws -> HAValue {
        let (data, _) = try await URLSession.shared.data(from: URL(string: address + "/test/" + path)!)
        return try JSONDecoder().decode(HAValue.self, from: data)
    }
}
