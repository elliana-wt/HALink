import Foundation

public struct Configuration: Codable, Equatable, Sendable {
    public var address: String
    public var devicesByServer: [String: [DeviceBinding]]
    public var servers: [ServerConnection]
    public init(address: String = "", devicesByServer: [String: [DeviceBinding]] = [:], servers: [ServerConnection]? = nil) {
        self.address = address; self.devicesByServer = devicesByServer
        self.servers = servers ?? Self.legacyServers(address: address, devicesByServer: devicesByServer)
    }
    public var devices: [DeviceBinding] {
        get { devicesByServer[address] ?? [] }
        set { devicesByServer[address] = newValue }
    }

    enum CodingKeys: String, CodingKey { case address, devicesByServer, servers }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        address = try values.decode(String.self, forKey: .address)
        devicesByServer = try values.decode([String: [DeviceBinding]].self, forKey: .devicesByServer)
        servers = try values.decodeIfPresent([ServerConnection].self, forKey: .servers)
            ?? Self.legacyServers(address: address, devicesByServer: devicesByServer)
    }

    @discardableResult
    public mutating func saveServer(id: UUID?, name: String, address input: String) throws -> ServerConnection {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw ServerConfigurationError.missingName }
        let normalized = try Endpoint(input).url.absoluteString
        guard !servers.contains(where: { $0.id != id && $0.address == normalized }) else {
            throw ServerConfigurationError.duplicateAddress
        }
        if let id {
            guard let index = servers.firstIndex(where: { $0.id == id }) else { throw ServerConfigurationError.missingServer }
            let oldAddress = servers[index].address
            if oldAddress != normalized {
                devicesByServer[normalized] = devicesByServer.removeValue(forKey: oldAddress) ?? []
                if address == oldAddress { address = normalized }
            }
            servers[index] = ServerConnection(id: id, name: name, address: normalized)
            return servers[index]
        }
        let server = ServerConnection(name: name, address: normalized)
        servers.append(server)
        return server
    }

    public mutating func removeServer(_ id: UUID) {
        guard let server = servers.first(where: { $0.id == id }) else { return }
        servers.removeAll { $0.id == id }
        devicesByServer[server.address] = nil
        if address == server.address { address = "" }
    }

    private static func legacyServers(address: String, devicesByServer: [String: [DeviceBinding]]) -> [ServerConnection] {
        var addresses = devicesByServer.keys.filter { !$0.isEmpty }.sorted()
        if !address.isEmpty {
            addresses.removeAll { $0 == address }
            addresses.insert(address, at: 0)
        }
        return addresses.map { ServerConnection(name: "Home Assistant", address: $0) }
    }
}

public struct ConfigurationStore: Sendable {
    public let file: URL
    public init(file: URL? = nil) {
        self.file = file ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            // Keep existing device configurations when upgrading from the first build.
            .appending(path: "Hestia/settings.json")
    }
    public func load() throws -> Configuration {
        guard FileManager.default.fileExists(atPath: file.path) else { return Configuration() }
        return try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: file))
    }
    public func save(_ config: Configuration) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(config).write(to: file, options: .atomic)
    }
}
