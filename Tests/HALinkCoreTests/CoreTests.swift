import Carbon
import Foundation
import HALinkCore
import Synchronization
import Testing

@Suite("地址、设备动作与配置")
struct CoreTests {
    @Test func localAddresses() throws {
        #expect(try Endpoint(" 192.168.1.10 ").url.absoluteString == "http://192.168.1.10:8123")
        #expect(try Endpoint("HOMEASSISTANT.local:8123/").url.host == "homeassistant.local")
        #expect(try Endpoint("https://ha.example.com/").api("states").absoluteString == "https://ha.example.com/api/states")
        #expect(try Endpoint("http://[::1]:8123").api("services/light/toggle").absoluteString == "http://[::1]:8123/api/services/light/toggle")
    }
    @Test(arguments: ["", "ftp://ha.local", "http://user:password@ha.local", "http://ha.local/dashboard", "http://ha.local/?token=secret", "http://ha.local/#page", "http://ha.local:0", "http://ha.local:65536", "not a host"])
    func rejectedAddresses(_ address: String) {
        #expect(throws: HAError.invalidAddress) { try Endpoint(address) }
    }
    @Test func f17WithoutFn() {
        let key = HotKey(keyCode: 64, modifiers: UInt32(1 << 23), label: "unimportant")
        #expect(key.displayName == "F17")
        #expect(key.modifiers == 0)
        #expect(key.isValid)
        #expect(!HotKey(keyCode: 0, modifiers: 0, label: "A").isValid)
        #expect(HotKey(keyCode: 0, modifiers: UInt32(cmdKey | optionKey), label: "A").displayName == "⌥⌘A")
    }
    @Test func capabilities() {
        let light = HAEntity(entityID: "light.screenbar", state: "on")
        #expect(DeviceAction.available(for: light, services: ["light.toggle", "light.turn_off"]) == [.toggle, .turnOff])
        let cover = HAEntity(entityID: "cover.blinds", state: "closed", attributes: .init(supportedFeatures: 3))
        #expect(DeviceAction.available(for: cover, services: ["cover.open_cover", "cover.close_cover", "cover.stop_cover"]) == [.open, .close])
        #expect(DeviceAction.candidates(for: "climate") == [.turnOn, .turnOff])
        #expect(DeviceAction.candidates(for: "sensor").isEmpty)
        let media = HAEntity(entityID: "media_player.speaker", state: "playing", attributes: .init(supportedFeatures: 128))
        #expect(DeviceAction.available(for: media, services: ["media_player.turn_on", "media_player.turn_off"]) == [.turnOn])
        let climate = HAEntity(entityID: "climate.ac", state: "heat", attributes: .init(supportedFeatures: 384))
        #expect(DeviceAction.available(for: climate, services: ["climate.turn_on", "climate.turn_off"]) == [.turnOn, .turnOff])
        #expect(HAEntity(entityID: "button.never_pressed", state: "unknown").isAvailable)
        #expect(HAEntity(entityID: "scene.never_used", state: "unknown").stateLabel == "可执行")
        #expect(!HAEntity(entityID: "light.unavailable", state: "unknown").isAvailable)
    }
    @Test func decodeHAStatesWithExtraFields() throws {
        let data = Data(#"{"entity_id":"light.screenbar","state":"on","attributes":{"friendly_name":"显示器挂灯","brightness":128,"supported_color_modes":["color_temp"]},"last_updated":"2026-11-13"}"#.utf8)
        let state = try JSONDecoder().decode(HAEntity.self, from: data)
        #expect(state.name == "显示器挂灯")
        #expect(state.stateLabel == "已开启")
    }
    @Test func devicePowerComesFromHAState() {
        #expect(HAEntity(entityID: "light.screenbar", state: "on").powerState == true)
        #expect(HAEntity(entityID: "light.screenbar", state: "off").powerState == false)
        #expect(HAEntity(entityID: "light.screenbar", state: "unavailable").powerState == nil)
        #expect(HAEntity(entityID: "light.screenbar", state: "unknown").powerState == nil)
        #expect(HAEntity(entityID: "climate.ac", state: "heat").powerState == true)
        #expect(HAEntity(entityID: "climate.ac", state: "off").powerState == false)
        #expect(HAEntity(entityID: "scene.goodnight", state: "on").powerState == nil)
        #expect(HAEntity(entityID: "cover.blinds", state: "open").powerState == nil)
    }
    @Test func oldDisabledShortcutConfigurationStillLoads() throws {
        let json = #"{"address":"http://ha.local:8123","shortcutsPaused":true,"devicesByServer":{"http://ha.local:8123":[{"id":"C27E8CFB-A21D-45C3-9E68-F0168393D145","entityID":"light.screenbar","name":"挂灯","action":"toggle","isEnabled":false,"shortcut":{"keyCode":64,"modifiers":0,"label":"F17"}}]}}"#
        let config = try JSONDecoder().decode(Configuration.self, from: Data(json.utf8))
        #expect(config.devices.count == 1)
        #expect(config.devices.first?.shortcut?.displayName == "F17")
        #expect(config.devices.first?.action == .toggle)
        #expect(config.devices.first?.icon == nil)
        #expect(config.devices.first?.iconColor == nil)
        let migrated = String(decoding: try JSONEncoder().encode(config), as: UTF8.self)
        #expect(!migrated.contains("isEnabled"))
        #expect(!migrated.contains("shortcutsPaused"))
    }
    @Test func isolatedServerConfiguration() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ConfigurationStore(file: folder.appending(path: "settings.json"))
        var config = Configuration(address: "http://192.168.1.10:8123")
        config.devices = [DeviceBinding(entityID: "light.screenbar", name: "挂灯", action: .toggle,
            shortcut: HotKey(keyCode: 64, modifiers: 0, label: "F17"))]
        config.address = "http://192.168.1.11:8123"
        #expect(config.devices.isEmpty)
        try store.save(config)
        var restored = try store.load()
        #expect(restored == config)
        restored.address = "http://192.168.1.10:8123"
        #expect(restored.devices.first?.shortcut?.displayName == "F17")
        #expect(restored.devices.first?.entityID == "light.screenbar")
    }
    @Test(arguments: [DeviceIcon.symbol("lamp.desk"), .emoji("💡"), .emoji("👩🏽‍💻"), .emoji("🇨🇳"), .emoji("1️⃣")])
    func customDeviceIconsPersist(_ icon: DeviceIcon) throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ConfigurationStore(file: folder.appending(path: "settings.json"))
        var config = Configuration(address: "http://ha.local:8123")
        let shortcut = HotKey(keyCode: 64, modifiers: 0, label: "F17")
        let color = DeviceIconColor(red: 0.8, green: 0.2, blue: 0.1)
        let binding = DeviceBinding(entityID: "light.screenbar", name: "挂灯", action: .toggle,
                                    shortcut: shortcut, icon: icon, iconColor: color)
        config.devices = [binding]
        try store.save(config)
        let restored = try store.load()
        #expect(restored.devices == [binding])
        #expect(restored.devices.first?.icon?.isValid == true)
        #expect(restored.devices.first?.iconColor == color)
        #expect(restored.devices.first?.shortcut == shortcut)
    }
    @Test(arguments: ["", "a", "1", "挂灯", "💡💡", "💡a"])
    func customEmojiRequiresOneEmoji(_ text: String) {
        #expect(!DeviceIcon.emoji(text).isValid)
    }
    @Test func namedServersPersistAndStaySeparate() throws {
        var config = Configuration()
        let home = try config.saveServer(id: nil, name: " 家里 ", address: "192.168.1.10:8123")
        config.address = home.address
        config.devices = [DeviceBinding(entityID: "light.screenbar", name: "挂灯", action: .toggle)]
        let office = try config.saveServer(id: nil, name: "办公室", address: "192.168.1.11:8123")
        config.address = office.address
        #expect(config.devices.isEmpty)
        config.devices = [DeviceBinding(entityID: "switch.desk", name: "办公桌", action: .toggle)]
        let restored = try JSONDecoder().decode(Configuration.self, from: JSONEncoder().encode(config))
        #expect(restored == config)
        #expect(restored.servers.map(\.name) == ["家里", "办公室"])
        #expect(restored.devices.first?.entityID == "switch.desk")
        #expect(restored.devicesByServer[home.address]?.first?.entityID == "light.screenbar")
    }
    @Test func addressEditPreservesIdentityAndShortcuts() throws {
        var config = Configuration(address: "http://192.168.1.10:8123")
        let server = try #require(config.servers.first)
        let binding = DeviceBinding(entityID: "light.screenbar", name: "挂灯", action: .toggle,
                                    shortcut: HotKey(keyCode: 64, modifiers: 0, label: "F17"))
        config.devices = [binding]
        let edited = try config.saveServer(id: server.id, name: "新家", address: "192.168.2.10:8123")
        #expect(edited.id == server.id)
        #expect(config.address == edited.address)
        #expect(config.devices == [binding])
        #expect(config.devicesByServer[server.address] == nil)
        #expect(config.servers.count == 1)
    }
    @Test func duplicateServerDoesNotOverwriteDevices() throws {
        var config = Configuration(address: "http://192.168.1.10:8123")
        config.devices = [DeviceBinding(entityID: "light.screenbar", name: "挂灯", action: .toggle)]
        let second = try config.saveServer(id: nil, name: "办公室", address: "192.168.1.11:8123")
        let original = config
        #expect(throws: ServerConfigurationError.duplicateAddress) {
            try config.saveServer(id: second.id, name: "其他", address: "192.168.1.10:8123")
        }
        #expect(config == original)
        #expect(throws: ServerConfigurationError.missingName) {
            try config.saveServer(id: nil, name: "  ", address: "192.168.1.12:8123")
        }
        #expect(config == original)
    }
    @Test func removingOneServerKeepsOtherServers() throws {
        var config = Configuration(address: "http://192.168.1.10:8123")
        let first = try #require(config.servers.first)
        config.devices = [DeviceBinding(entityID: "light.a", name: "A", action: .toggle)]
        let second = try config.saveServer(id: nil, name: "办公室", address: "192.168.1.11:8123")
        config.address = second.address
        config.devices = [DeviceBinding(entityID: "light.b", name: "B", action: .toggle)]
        config.removeServer(first.id)
        #expect(config.servers == [second])
        #expect(config.address == second.address)
        #expect(config.devices.first?.entityID == "light.b")
        #expect(config.devicesByServer[first.address] == nil)
        config.removeServer(second.id)
        #expect(config.address.isEmpty)
        #expect(config.devices.isEmpty)
        #expect(config.servers.isEmpty)
    }
    @Test func legacyConnectionMigratesIntoServerList() throws {
        let old = #"{"address":"http://192.168.1.10:8123","devicesByServer":{"http://192.168.1.10:8123":[{"id":"C27E8CFB-A21D-45C3-9E68-F0168393D145","entityID":"light.screenbar","name":"挂灯","action":"toggle","shortcut":{"keyCode":64,"modifiers":0,"label":"F17"}}],"http://192.168.1.11:8123":[]}}"#
        let migrated = try JSONDecoder().decode(Configuration.self, from: Data(old.utf8))
        #expect(migrated.servers.count == 2)
        #expect(migrated.servers.first?.address == migrated.address)
        #expect(migrated.devices.first?.shortcut?.displayName == "F17")
        let restored = try JSONDecoder().decode(Configuration.self, from: JSONEncoder().encode(migrated))
        #expect(restored == migrated)
    }
    @Test func releaseVersionsCompareNumerically() throws {
        #expect(try ReleaseVersion("v1.10.0") > ReleaseVersion("1.9.9"))
        #expect(try ReleaseVersion("1.4") == ReleaseVersion("1.4.0"))
        #expect(try ReleaseVersion("v1.4.0+build9") == ReleaseVersion("1.4.0"))
        #expect(throws: UpdateError.invalidVersion) { try ReleaseVersion("1.4.0-beta") }
        #expect(throws: UpdateError.invalidVersion) { try ReleaseVersion("+123") }
    }
}

private final class StubProtocol: URLProtocol, @unchecked Sendable {
    static let handler = Mutex<(@Sendable (URLRequest) throws -> (Int, Data))?>(nil)
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let callback = Self.handler.withLock { $0 }
            let unwrapped = try #require(callback)
            let (status, data) = try unwrapped(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type":"application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

@Suite("HA 请求与失败处理", .serialized)
struct ClientTests {
    private func updater() -> UpdateService {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        return UpdateService(session: URLSession(configuration: config))
    }
    private func client() throws -> HAClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        return try HAClient(endpoint: Endpoint("http://127.0.0.1:8123"), token: "test-token", session: URLSession(configuration: config))
    }
    @Test func stateAndServices() async throws {
        StubProtocol.handler.withLock { handler in
            handler = { request in
                #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
                #expect(request.httpMethod == "GET")
                let json = request.url!.path.hasSuffix("services")
                    ? #"[{"domain":"light","services":{"toggle":{"name":"Toggle"},"turn_on":{}}}]"#
                    : #"[{"entity_id":"light.screenbar","state":"off","attributes":{"friendly_name":"挂灯"}}]"#
                return (200, Data(json.utf8))
            }
        }
        let client = try client()
        #expect(try await client.states().first?.name == "挂灯")
        #expect(try await client.services() == ["light.toggle", "light.turn_on"])
    }
    @Test func actionPayloadAndNoRetry() async throws {
        let count = Mutex(0)
        StubProtocol.handler.withLock { handler in
            handler = { request in
                count.withLock { $0 += 1 }
                #expect(request.httpMethod == "POST")
                #expect(request.url?.path == "/api/services/light/toggle")
                let body: Data
                if let data = request.httpBody { body = data }
                else if let stream = request.httpBodyStream {
                    stream.open(); defer { stream.close() }
                    var data = Data(); var buffer = [UInt8](repeating: 0, count: 1024)
                    while stream.hasBytesAvailable {
                        let size = stream.read(&buffer, maxLength: buffer.count)
                        if size <= 0 { break }; data.append(contentsOf: buffer.prefix(size))
                    }
                    body = data
                } else { body = Data() }
                let payload = try JSONDecoder().decode([String:String].self, from: body)
                #expect(payload == ["entity_id":"light.screenbar"])
                return (500, Data())
            }
        }
        let binding = DeviceBinding(entityID: "light.screenbar", name: "挂灯", action: .toggle)
        await #expect(throws: HAError.response(500)) { try await client().perform(binding) }
        #expect(count.withLock { $0 } == 1)
    }
    @Test(arguments: [DeviceAction.turnOn, .turnOff])
    func explicitPowerRequests(_ action: DeviceAction) async throws {
        StubProtocol.handler.withLock { handler in
            handler = { request in
                #expect(request.httpMethod == "POST")
                #expect(request.url?.path == "/api/services/light/\(action.rawValue)")
                return (200, Data("[]".utf8))
            }
        }
        let saved = DeviceBinding(entityID: "light.screenbar", name: "挂灯", action: .toggle,
                                  shortcut: HotKey(keyCode: 64, modifiers: 0, label: "F17"))
        var command = saved
        command.action = action
        try await client().perform(command)
        #expect(saved.action == .toggle)
        #expect(saved.shortcut?.displayName == "F17")
    }
    @Test(arguments: [401,403,404,302,503])
    func statusErrors(_ code: Int) async throws {
        StubProtocol.handler.withLock { $0 = { _ in (code, Data()) } }
        let expected: HAError = switch code {
        case 401: .unauthorized
        case 403: .forbidden
        case 404: .notFound
        case 302: .redirected
        default: .response(code)
        }
        await #expect(throws: expected) { try await client().states() }
    }
    @Test func malformedResponse() async throws {
        StubProtocol.handler.withLock { $0 = { _ in (200, Data("<html>login</html>".utf8)) } }
        await #expect(throws: HAError.invalidResponse) { try await client().states() }
    }
    @Test func emptyTokenRejected() throws {
        #expect(throws: HAError.missingToken) { try HAClient(endpoint: Endpoint("ha.local:8123"), token: " \n ") }
    }
    @Test func unpublishedUpdatesNeverMakeANetworkRequest() async throws {
        let requests = Mutex(0)
        StubProtocol.handler.withLock { handler in
            handler = { _ in
                requests.withLock { $0 += 1 }
                return (200, Data())
            }
        }
        await #expect(throws: UpdateError.notPublished) { try await updater().latestRelease(repository: nil) }
        await #expect(throws: UpdateError.invalidRepository) {
            try await updater().latestRelease(repository: "https://example.com/other")
        }
        #expect(requests.withLock { $0 } == 0)
    }
    @Test func updateRequestNeverUsesHACredentials() async throws {
        StubProtocol.handler.withLock { handler in
            handler = { request in
                #expect(request.url?.absoluteString == "https://api.github.com/repos/test/HALink/releases/latest")
                #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
                #expect(request.value(forHTTPHeaderField: "Accept") == "application/vnd.github+json")
                return (200, Data(#"{"tag_name":"v1.5.0","html_url":"https://github.com/test/HALink/releases/tag/v1.5.0"}"#.utf8))
            }
        }
        let release = try await updater().latestRelease(repository: "test/HALink")
        #expect(release.tagName == "v1.5.0")
    }
    @Test func updateSourceFailuresAreNotReportedAsUpToDate() async throws {
        StubProtocol.handler.withLock { $0 = { _ in (404, Data()) } }
        await #expect(throws: UpdateError.notPublished) { try await updater().latestRelease(repository: "test/HALink") }
        StubProtocol.handler.withLock { $0 = { _ in (403, Data()) } }
        await #expect(throws: UpdateError.rateLimited) { try await updater().latestRelease(repository: "test/HALink") }
        StubProtocol.handler.withLock { $0 = { _ in (200, Data(#"{"tag_name":"v1.5.0","html_url":"https://example.com/download"}"#.utf8)) } }
        await #expect(throws: UpdateError.invalidResponse) { try await updater().latestRelease(repository: "test/HALink") }
    }
}
