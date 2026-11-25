import Foundation

public struct HAHomeMetadata: Equatable, Sendable {
    public struct Area: Codable, Equatable, Identifiable, Sendable {
        public let areaID: String
        public let name: String
        public var id: String { areaID }
        enum CodingKeys: String, CodingKey { case areaID = "area_id", name }
    }
    public struct Device: Codable, Equatable, Sendable {
        public let id: String
        public let areaID: String?
        enum CodingKeys: String, CodingKey { case id, areaID = "area_id" }
    }
    public struct Entity: Codable, Equatable, Sendable {
        public let entityID: String
        public let areaID: String?
        public let deviceID: String?
        enum CodingKeys: String, CodingKey { case entityID = "entity_id", areaID = "area_id", deviceID = "device_id" }
    }
    public var areas: [Area] = []
    public var devices: [Device] = []
    public var entities: [Entity] = []
    public var temperatureUnit = "°"
    public init() {}

    public func areaID(for entityID: String) -> String? {
        guard let entity = entities.first(where: { $0.entityID == entityID }) else { return nil }
        return entity.areaID ?? devices.first(where: { $0.id == entity.deviceID })?.areaID
    }
}

public struct HAStateChange: Equatable, Sendable {
    public let entityID: String
    public let state: HAEntity?
    public let timeFired: String?
}

public struct HAWebSocketMessage: Decodable, Sendable {
    public struct Event: Decodable, Sendable {
        public let eventType: String
        public let data: HAValue
        public let timeFired: String?
        enum CodingKeys: String, CodingKey { case eventType = "event_type", data, timeFired = "time_fired" }
    }
    public let type: String
    public let id: Int?
    public let success: Bool?
    public let result: HAValue?
    public let event: Event?

    public func stateChange() throws -> HAStateChange? {
        guard type == "event", let event, event.eventType == "state_changed",
              let entityID = event.data["entity_id"]?.string,
              let value = event.data["new_state"] else { return nil }
        let state = value == .null ? nil : try value.decoded(HAEntity.self)
        guard state == nil || state?.id == entityID else { throw HAError.invalidResponse }
        return HAStateChange(entityID: entityID, state: state, timeFired: event.timeFired)
    }
}

/// Replays changes received while a snapshot is in flight without restoring an older state.
public enum HASnapshot {
    public static func merging(_ snapshot: [HAEntity], changes: [HAStateChange]) -> [HAEntity] {
        var states = Dictionary(snapshot.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        for change in changes {
            let oldDate = date(states[change.entityID]?.lastUpdated)
            let newDate = date(change.state?.lastUpdated ?? change.timeFired)
            if let oldDate, let newDate, newDate < oldDate { continue }
            states[change.entityID] = change.state
        }
        return Array(states.values)
    }
    private static func date(_ string: String?) -> Date? {
        guard let string else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}

@MainActor
public final class HARealtime {
    public enum Status: Equatable, Sendable { case stopped, connecting, live, reconnecting, unauthorized }
    public enum Update: Sendable {
        case snapshot([HAEntity]), change(HAStateChange), metadata(HAHomeMetadata)
    }
    public var onUpdate: ((Update) -> Void)?
    public var onStatus: ((Status) -> Void)?
    private let endpoint: Endpoint
    private let token: String
    private let session: URLSession
    private var task: Task<Void, Never>?
    private var socket: URLSessionWebSocketTask?
    private var generation = UUID()

    public init(endpoint: Endpoint, token: String) {
        self.endpoint = endpoint; self.token = token
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 0
        config.httpCookieStorage = nil; config.urlCache = nil
        session = URLSession(configuration: config, delegate: NoRedirects(), delegateQueue: nil)
    }

    nonisolated public static func url(for endpoint: Endpoint) -> URL {
        // Endpoint guarantees a valid root HTTP(S) URL, including IPv6 addresses.
        var parts = URLComponents(url: endpoint.api("websocket"), resolvingAgainstBaseURL: false)!
        parts.scheme = parts.scheme == "https" ? "wss" : "ws"
        return parts.url!
    }

    public func start() {
        stop()
        let attempt = generation
        task = Task { [weak self] in
            var retry = 1
            while !Task.isCancelled {
                guard let self, attempt == self.generation else { return }
                self.onStatus?(retry == 1 ? .connecting : .reconnecting)
                do {
                    try await self.run(attempt: attempt)
                } catch HAError.unauthorized {
                    guard attempt == self.generation else { return }
                    self.onStatus?(.unauthorized)
                    return
                } catch {
                    guard attempt == self.generation, !Task.isCancelled else { return }
                    self.onStatus?(.reconnecting)
                }
                do { try await Task.sleep(for: .seconds(retry)) } catch { return }
                retry = min(retry * 2, 15)
            }
        }
    }

    public func stop() {
        generation = UUID()
        task?.cancel(); task = nil
        socket?.cancel(with: .goingAway, reason: nil); socket = nil
        onStatus?(.stopped)
    }

    private func run(attempt: UUID) async throws {
        let socket = session.webSocketTask(with: Self.url(for: endpoint))
        self.socket = socket
        socket.resume()
        let deadline = Task {
            do { try await Task.sleep(for: .seconds(15)) } catch { return }
            socket.cancel(with: .goingAway, reason: nil)
        }
        var heartbeat: Task<Void, Never>?
        defer { deadline.cancel(); heartbeat?.cancel(); socket.cancel(with: .goingAway, reason: nil) }
        guard try await receive(socket).type == "auth_required" else { throw HAError.invalidResponse }
        try Task.checkCancellation()
        guard attempt == generation else { throw CancellationError() }
        try await send(["type": .string("auth"), "access_token": .string(token)], to: socket)
        let auth = try await receive(socket)
        if auth.type == "auth_invalid" { throw HAError.unauthorized }
        guard auth.type == "auth_ok" else { throw HAError.invalidResponse }
        try await send(["id": .number(1), "type": .string("subscribe_events"), "event_type": .string("state_changed")], to: socket)
        let subscription = try await receive(socket)
        guard subscription.type == "result", subscription.id == 1, subscription.success == true else {
            throw HAError.invalidResponse
        }
        try await send(["id": .number(2), "type": .string("get_states")], to: socket)
        var nextID = 3
        var pending: [Int: String] = [:]
        var pingID: Int?
        var ready = false
        var changes: [HAStateChange] = []
        var metadata = HAHomeMetadata()

        func request(_ type: String) async throws {
            let id = nextID; nextID += 1
            pending[id] = type
            try await send(["id": .number(Double(id)), "type": .string(type)], to: socket)
        }

        while !Task.isCancelled, attempt == generation {
            let message = try await receive(socket)
            guard attempt == generation, !Task.isCancelled else { throw CancellationError() }
            if message.type == "auth_invalid" { throw HAError.unauthorized }
            if message.type == "pong", message.id == pingID { pingID = nil; continue }
            if let change = try message.stateChange() {
                if ready { onUpdate?(.change(change)) }
                else {
                    guard changes.count < 20_000 else { throw HAError.invalidResponse }
                    changes.append(change)
                }
            } else if message.type == "result", message.id == 2 {
                guard message.success == true, let result = message.result else { throw HAError.invalidResponse }
                let snapshot = try result.decoded([HAEntity].self)
                onUpdate?(.snapshot(HASnapshot.merging(snapshot, changes: changes)))
                ready = true; changes.removeAll()
                deadline.cancel(); onStatus?(.live)
                try await request("get_config")
                try await request("config/area_registry/list")
                try await request("config/device_registry/list")
                try await request("config/entity_registry/list")
                for event in ["area_registry_updated", "device_registry_updated", "entity_registry_updated"] {
                    let id = nextID; nextID += 1
                    try await send(["id": .number(Double(id)), "type": .string("subscribe_events"),
                                    "event_type": .string(event)], to: socket)
                }
                heartbeat = Task {
                    while !Task.isCancelled {
                        do { try await Task.sleep(for: .seconds(25)) } catch { return }
                        guard self.generation == attempt else { return }
                        if pingID != nil { socket.cancel(with: .goingAway, reason: nil); return }
                        let id = nextID; nextID += 1; pingID = id
                        do { try await self.send(["id": .number(Double(id)), "type": .string("ping")], to: socket) }
                        catch { socket.cancel(with: .goingAway, reason: nil); return }
                    }
                }
            } else if message.type == "result", let id = message.id, let type = pending.removeValue(forKey: id),
                      message.success == true, let result = message.result {
                // Registries can be unavailable to restricted HA users; device control still works.
                switch type {
                case "get_config": metadata.temperatureUnit = result["unit_system"]?["temperature"]?.string ?? "°"
                case "config/area_registry/list": metadata.areas = (try? result.decoded([HAHomeMetadata.Area].self)) ?? []
                case "config/device_registry/list": metadata.devices = (try? result.decoded([HAHomeMetadata.Device].self)) ?? []
                case "config/entity_registry/list": metadata.entities = (try? result.decoded([HAHomeMetadata.Entity].self)) ?? []
                default: break
                }
                onUpdate?(.metadata(metadata))
            } else if let type = message.event?.eventType, type.hasSuffix("_registry_updated") {
                // A room or device can move while the panel is open.
                let registry = String(type.dropLast("_updated".count))
                let command = "config/\(registry)/list"
                if !pending.values.contains(command) { try await request(command) }
            }
        }
        throw CancellationError()
    }

    private func receive(_ socket: URLSessionWebSocketTask) async throws -> HAWebSocketMessage {
        let message = try await socket.receive()
        let data: Data
        switch message {
        case .string(let string): data = Data(string.utf8)
        case .data(let bytes): data = bytes
        @unknown default: throw HAError.invalidResponse
        }
        return try JSONDecoder().decode(HAWebSocketMessage.self, from: data)
    }
    private func send(_ value: [String: HAValue], to socket: URLSessionWebSocketTask) async throws {
        let data = try JSONEncoder().encode(value)
        try await socket.send(.string(String(decoding: data, as: UTF8.self)))
    }
}
