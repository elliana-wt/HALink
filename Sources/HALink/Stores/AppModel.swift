import AppKit
import HALinkCore
import Observation
import ServiceManagement

@Observable
final class AppModel {
    enum UpdateState: Equatable {
        case idle, checking, upToDate, notPublished
        case available(String, URL)
        case failed(String)
    }
    enum ConnectionState: Equatable {
        case notConfigured, connecting, connected, offline
        var title: String {
            switch self {
            case .notConfigured: "尚未连接"
            case .connecting: "正在连接…"
            case .connected: "已连接"
            case .offline: "连接中断"
            }
        }
    }
    private(set) var config = Configuration()
    private(set) var entities: [String: HAEntity] = [:]
    private(set) var services: Set<String> = []
    private(set) var connectionState: ConnectionState = .notConfigured
    private(set) var connectionError: String?
    private(set) var shortcutErrors: [UUID: String] = [:]
    private(set) var actionErrors: [UUID: String] = [:]
    private(set) var busyIDs: Set<UUID> = []
    private(set) var lastAction: String?
    private(set) var lastRefresh: Date?
    private(set) var realtimeStatus: HARealtime.Status = .stopped
    private(set) var homeMetadata = HAHomeMetadata()
    private(set) var updateState: UpdateState = .idle
    var generalError: String?
    var launchAtLogin = SMAppService.mainApp.status == .enabled
    var isRecording = false
    let homePhoto: HomePhotoStore
    @ObservationIgnored private let configStore = ConfigurationStore()
    @ObservationIgnored private let keychain = KeychainStore()
    @ObservationIgnored let hotKeys = HotKeyManager()
    @ObservationIgnored private var client: HAClient?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var realtime: HARealtime?
    @ObservationIgnored private var entityRevisions: [String: UInt64] = [:]
    @ObservationIgnored private var pendingControls: [String: [HAControl]] = [:]
    @ObservationIgnored private var controlTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var climateModes: [String: String] = [:]
    @ObservationIgnored private var refreshing = false
    @ObservationIgnored private var stateRevision: UInt64 = 0
    @ObservationIgnored private var lastPress: [String: Date] = [:]
    @ObservationIgnored private var loadFailed = false

    var devices: [DeviceBinding] { config.devices }
    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.4.0"
    }
    var address: String { config.address }
    var servers: [ServerConnection] { config.servers }
    var currentServerName: String {
        servers.first(where: { $0.address == address })?.name ?? "未连接服务器"
    }
    var isConnected: Bool { connectionState == .connected }
    var canSend: Bool { client != nil && connectionState != .connecting }
    var selectableEntities: [HAEntity] {
        entities.values.filter { !availableActions($0).isEmpty }.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    init(configuration: Configuration? = nil, client: HAClient? = nil, homePhoto: HomePhotoStore = HomePhotoStore()) {
        self.client = client
        self.homePhoto = homePhoto
        if let configuration { config = configuration }
        else {
            do { config = try configStore.load() }
            catch { generalError = "无法读取设备配置。为保护现有数据，本次不会覆盖它。"; loadFailed = true }
        }
        hotKeys.onPress = { [weak self] id in self?.run(id) }
    }

    func start() async {
        if client != nil {
            connectionState = .offline
            await refresh()
            startRealtime()
        } else if !address.isEmpty {
            do {
                let endpoint = try Endpoint(address)
                if let token = try keychain.read(address: address) {
                    client = try HAClient(endpoint: endpoint, token: token)
                    connectionState = .offline
                    await refresh()
                    startRealtime()
                } else { connectionError = "请在连接设置中重新填写 Token。" }
            } catch { connectionError = error.localizedDescription }
        }
        rebindShortcuts()
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(15)) } catch { break }
                guard let self else { break }
                await self.refresh()
            }
        }
    }

    @discardableResult
    func connect(serverID: UUID?, name: String, address input: String, token draft: String) async -> Bool {
        guard connectionState != .connecting, !loadFailed else { return false }
        let previousState = connectionState
        connectionError = nil
        connectionState = .connecting
        generation = UUID()
        realtime?.stop()
        realtimeStatus = .stopped
        cancelControls()
        let attempt = generation
        do {
            let endpoint = try Endpoint(input)
            let normalized = endpoint.url.absoluteString
            var next = config
            try next.saveServer(id: serverID, name: name, address: normalized)
            var token = draft.trimmingCharacters(in: .whitespacesAndNewlines)
            let originalAddress = serverID.flatMap { id in servers.first(where: { $0.id == id })?.address }
            if token.isEmpty, normalized == originalAddress {
                token = try keychain.read(address: normalized) ?? ""
            }
            let candidate = try HAClient(endpoint: endpoint, token: token)
            async let states = candidate.states()
            async let actions = candidate.services()
            let (fetched, registered) = try await (states, actions)
            guard attempt == generation else { return false }
            try keychain.save(token, address: normalized)
            next.address = normalized
            try configStore.save(next)
            config = next
            client = candidate
            entities = Dictionary(fetched.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
            services = registered
            homeMetadata = HAHomeMetadata(); entityRevisions = [:]; climateModes = [:]
            for entity in fetched { rememberMode(entity) }
            actionErrors.removeAll(); lastAction = nil
            lastRefresh = Date(); connectionState = .connected
            rebindShortcuts()
            startRealtime()
            return true
        } catch {
            guard attempt == generation else { return false }
            connectionError = friendly(error)
            connectionState = client == nil ? .notConfigured : previousState
            startRealtime()
            return false
        }
    }

    func refresh() async {
        guard let client, !refreshing, busyIDs.isEmpty, connectionState != .connecting else { return }
        let attempt = generation
        let revision = stateRevision
        refreshing = true
        defer { refreshing = false }
        do {
            async let states = client.states()
            async let actions = client.services()
            let (fetched, registered) = try await (states, actions)
            guard attempt == generation else { return }
            services = registered
            guard revision == stateRevision else { return }
            entities = Dictionary(fetched.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
            for entity in fetched { rememberMode(entity) }
            lastRefresh = Date(); connectionState = .connected; connectionError = nil
        } catch {
            guard attempt == generation, revision == stateRevision else { return }
            if realtimeStatus != .live { connectionState = .offline; connectionError = friendly(error) }
        }
    }

    func disconnect() {
        generation = UUID()
        realtime?.stop(); realtime = nil
        realtimeStatus = .stopped
        cancelControls()
        homeMetadata = HAHomeMetadata(); entityRevisions = [:]; climateModes = [:]
        client = nil; entities.removeAll(); services.removeAll()
        connectionState = .notConfigured; connectionError = nil; lastAction = nil
        hotKeys.stop()
    }

    func stop() {
        pollTask?.cancel(); pollTask = nil
        realtime?.stop(); realtime = nil
        cancelControls(); hotKeys.stop()
    }

    private func startRealtime() {
        realtime?.stop()
        guard let client else { realtime = nil; return }
        let attempt = generation
        let realtime = client.realtime()
        self.realtime = realtime
        realtime.onStatus = { [weak self] status in
            guard let self, self.generation == attempt else { return }
            self.realtimeStatus = status
            if status == .live { self.connectionState = .connected; self.connectionError = nil }
            if status == .unauthorized { self.connectionState = .offline; self.connectionError = HAError.unauthorized.localizedDescription }
        }
        realtime.onUpdate = { [weak self] update in
            guard let self, self.generation == attempt else { return }
            switch update {
            case .snapshot(let states):
                self.stateRevision &+= 1
                let previousIDs = Set(self.entities.keys)
                self.entities = Dictionary(states.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
                for entity in states { self.rememberMode(entity) }
                for id in previousIDs.union(self.entities.keys) { self.entityRevisions[id, default: 0] &+= 1 }
                self.lastRefresh = Date()
            case .change(let change):
                self.stateRevision &+= 1
                self.entityRevisions[change.entityID, default: 0] &+= 1
                self.entities[change.entityID] = change.state
                if let entity = change.state { self.rememberMode(entity) }
                self.lastRefresh = Date()
            case .metadata(let metadata): self.homeMetadata = metadata
            }
        }
        realtime.start()
    }

    func areaName(for entityID: String) -> String? {
        guard let id = homeMetadata.areaID(for: entityID) else { return nil }
        return homeMetadata.areas.first(where: { $0.id == id })?.name
    }

    func supportsDetails(_ binding: DeviceBinding) -> Bool {
        guard let entity = entities[binding.entityID] else { return false }
        return Self.supportsDetails(for: entity, services: services)
    }

    static func supportsDetails(for entity: HAEntity, services: Set<String>) -> Bool {
        switch entity.domain {
        case "light":
            guard services.contains("light.turn_on") else { return false }
            return entity.supportsBrightness || entity.colorTemperatureRange != nil || entity.supportsColor
        case "climate":
            let a = entity.attributes
            if entity.temperatureRange != nil, entity.supportsTargetRange || entity.supportsTargetTemperature,
               services.contains("climate.set_temperature") { return true }
            if let modes = a.hvacModes, !modes.isEmpty, services.contains("climate.set_hvac_mode") { return true }
            if entity.hasFeature(8), let modes = a.fanModes, !modes.isEmpty, services.contains("climate.set_fan_mode") { return true }
            if entity.hasFeature(32), let modes = a.swingModes, !modes.isEmpty, services.contains("climate.set_swing_mode") { return true }
            if entity.hasFeature(512), let modes = a.swingHorizontalModes, !modes.isEmpty,
               services.contains("climate.set_swing_horizontal_mode") { return true }
            if entity.hasFeature(16), let presets = a.presetModes, !presets.isEmpty,
               services.contains("climate.set_preset_mode") { return true }
            return false
        default:
            return false
        }
    }

    /// Coalesce unsent slider values and serialize commands for the same physical entity.
    func setControl(_ id: UUID, _ control: HAControl) {
        guard isConnected, client != nil, let binding = devices.first(where: { $0.id == id }),
              entities[binding.entityID]?.isAvailable == true else { return }
        let entityID = binding.entityID
        pendingControls[entityID, default: []].removeAll { $0.key == control.key }
        pendingControls[entityID, default: []].append(control)
        guard controlTasks[entityID] == nil else { return }
        let attempt = generation
        controlTasks[entityID] = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled, attempt == self.generation,
                  let queue = self.pendingControls[entityID], !queue.isEmpty {
                let related = Set(self.devices.filter { $0.entityID == entityID }.map(\.id))
                if !self.busyIDs.isDisjoint(with: related) {
                    do { try await Task.sleep(for: .milliseconds(50)) } catch { break }
                    continue
                }
                guard let client = self.client, let entity = self.entities[entityID] else { break }
                let command = self.pendingControls[entityID]!.removeFirst()
                self.busyIDs.formUnion(related)
                self.stateRevision &+= 1
                for id in related { self.actionErrors[id] = nil }
                do {
                    let request = try HAControlRequest(entity: entity, control: command, services: self.services)
                    try await client.perform(request)
                    guard attempt == self.generation else { return }
                    self.lastAction = "指令已发送：\(binding.name)"
                    do {
                        var updated = try await self.readState(entityID, client: client, attempt: attempt)
                        for _ in 0..<4 where !request.isConfirmed(by: updated) {
                            try await Task.sleep(for: .milliseconds(400))
                            guard attempt == self.generation else { return }
                            updated = try await self.readState(entityID, client: client, attempt: attempt)
                        }
                        if !request.isConfirmed(by: updated) {
                            for id in related { self.actionErrors[id] = "指令已发送，设备状态尚未确认。请稍后刷新。" }
                        }
                    }
                    catch {
                        guard attempt == self.generation else { return }
                        for id in related { self.actionErrors[id] = "指令已发送，但未能确认设备状态。请刷新后查看。" }
                    }
                } catch {
                    guard attempt == self.generation else { return }
                    for id in related { self.actionErrors[id] = self.friendly(error) }
                    // Reconcile after errors, without replaying the command.
                    _ = try? await self.readState(entityID, client: client, attempt: attempt)
                }
                guard attempt == self.generation else { return }
                self.busyIDs.subtract(related)
            }
            guard attempt == self.generation else { return }
            self.controlTasks[entityID] = nil
            self.pendingControls[entityID] = nil
        }
    }

    private func cancelControls() {
        for task in controlTasks.values { task.cancel() }
        controlTasks = [:]; pendingControls = [:]; busyIDs = []; lastPress = [:]
    }

    private func readState(_ id: String, client: HAClient, attempt: UUID) async throws -> HAEntity {
        let revision = entityRevisions[id, default: 0]
        let fetched = try await client.state(id)
        guard attempt == generation else { throw CancellationError() }
        if entityRevisions[id, default: 0] == revision { entities[id] = fetched; rememberMode(fetched) }
        return entities[id] ?? fetched
    }

    private func rememberMode(_ entity: HAEntity) {
        if entity.domain == "climate", entity.powerState == true { climateModes[entity.id] = entity.state }
    }

    @discardableResult
    func removeServer(_ id: UUID) -> Bool {
        guard connectionState != .connecting,
              let server = servers.first(where: { $0.id == id }), !loadFailed else { return false }
        var next = config
        next.removeServer(id)
        do {
            let previousToken = try keychain.read(address: server.address)
            try keychain.remove(address: server.address)
            do { try configStore.save(next) }
            catch {
                if let previousToken {
                    do { try keychain.save(previousToken, address: server.address) }
                    catch {
                        connectionError = "配置未能保存，Token 也未能恢复。请为这台服务器重新填写 Token。"
                        return false
                    }
                }
                throw error
            }
            let wasCurrent = address == server.address
            config = next
            if wasCurrent { disconnect() }
            else { rebindShortcuts() }
            return true
        } catch {
            connectionError = friendly(error)
            return false
        }
    }

    func availableActions(_ entity: HAEntity) -> [DeviceAction] {
        DeviceAction.available(for: entity, services: services)
    }
    func save(_ binding: DeviceBinding) -> Bool {
        if let shortcut = binding.shortcut,
           devices.contains(where: { $0.id != binding.id && $0.shortcut?.matches(shortcut) == true }) {
            generalError = "这个快捷键已经分配给另一个设备。"; return false
        }
        var next = config
        var devices = next.devices
        if let index = devices.firstIndex(where: { $0.id == binding.id }) { devices[index] = binding }
        else { devices.append(binding) }
        next.devices = devices
        return commit(next)
    }
    func remove(_ id: UUID) {
        var next = config
        next.devices.removeAll { $0.id == id }
        if commit(next) { actionErrors[id] = nil }
    }
    func beginRecording() { isRecording = true; hotKeys.stop() }
    func endRecording() { isRecording = false; rebindShortcuts() }

    func validateShortcut(_ shortcut: HotKey?, for id: UUID) -> String? {
        guard let shortcut else { return nil }
        guard shortcut.isValid else { return "请使用 F1–F20，或包含 ⌘、⌥、⌃ 的组合键。" }
        if devices.contains(where: { $0.id != id && $0.shortcut?.matches(shortcut) == true }) {
            return "这个快捷键已分配给另一个设备。"
        }
        do { try hotKeys.register(shortcut, id: id); hotKeys.unregister(id); return nil }
        catch { return error.localizedDescription }
    }

    func rebindShortcuts() {
        hotKeys.stop(); shortcutErrors.removeAll()
        guard !isRecording, client != nil else { return }
        for binding in devices {
            guard let shortcut = binding.shortcut else { continue }
            do { try hotKeys.register(shortcut, id: binding.id) }
            catch { shortcutErrors[binding.id] = error.localizedDescription }
        }
    }

    func run(_ id: UUID) {
        perform(id, override: nil)
    }

    func supportsPowerControl(_ binding: DeviceBinding) -> Bool {
        guard let entity = entities[binding.entityID],
              ["light", "switch", "fan", "input_boolean", "climate", "media_player"].contains(entity.domain) else { return false }
        let actions = availableActions(entity)
        return actions.contains(.turnOn) && actions.contains(.turnOff)
    }

    func setPower(_ id: UUID, isOn: Bool) {
        guard let binding = devices.first(where: { $0.id == id }), supportsPowerControl(binding) else { return }
        perform(id, override: isOn ? .turnOn : .turnOff)
    }

    private func perform(_ id: UUID, override: DeviceAction?) {
        guard let client, connectionState != .connecting,
              var binding = devices.first(where: { $0.id == id }) else { return }
        let relatedIDs = Set(devices.filter { $0.entityID == binding.entityID }.map(\.id))
        guard busyIDs.isDisjoint(with: relatedIDs),
              Date().timeIntervalSince(lastPress[binding.entityID] ?? .distantPast) > 0.4 else { return }
        if let override { binding.action = override }
        let attempt = generation
        stateRevision &+= 1
        busyIDs.formUnion(relatedIDs)
        lastPress[binding.entityID] = Date()
        for relatedID in relatedIDs { actionErrors[relatedID] = nil }
        Task {
            defer { if attempt == generation { busyIDs.subtract(relatedIDs) } }
            do {
                let current = try await readState(binding.entityID, client: client, attempt: attempt)
                guard attempt == generation else { return }
                guard current.isAvailable else { actionErrors[id] = "设备当前不可用，请检查设备连接。"; return }
                let expectedPower: Bool? = current.powerState.flatMap { state in
                    switch binding.action {
                    case .turnOn: true
                    case .turnOff: false
                    case .toggle: !state
                    default: nil
                    }
                }
                if current.domain == "climate", binding.action == .turnOn || binding.action == .turnOff,
                   !(current.hasFeature(binding.action == .turnOn ? 256 : 128) && services.contains("climate.\(binding.action.rawValue)")) {
                    let modes = current.attributes.hvacModes ?? []
                    let previous = climateModes[current.id].flatMap { modes.contains($0) ? $0 : nil }
                    let mode = binding.action == .turnOff ? "off" : previous ?? modes.first(where: { $0 != "off" }) ?? ""
                    try await client.perform(HAControlRequest(entity: current, control: .hvacMode(mode), services: services))
                } else {
                    try await client.perform(binding)
                }
                guard attempt == generation else { return }
                // Never infer power state from the clicked switch or replay a toggle on failure.
                do {
                    var updated = try await readState(binding.entityID, client: client, attempt: attempt)
                    guard attempt == generation else { return }
                    if let expectedPower {
                        for _ in 0..<4 where updated.powerState != expectedPower {
                            try await Task.sleep(for: .milliseconds(500))
                            guard attempt == generation else { return }
                            updated = try await readState(binding.entityID, client: client, attempt: attempt)
                            guard attempt == generation else { return }
                        }
                        if updated.powerState != expectedPower {
                            actionErrors[id] = "指令已发送，设备状态尚未确认。请刷新后查看。"
                        }
                    }
                    connectionState = .connected; connectionError = nil
                    lastAction = actionErrors[id] == nil
                        ? "已执行：\(binding.name) · \(binding.action.title)"
                        : "指令已发送：\(binding.name)"
                } catch {
                    guard attempt == generation else { return }
                    actionErrors[id] = "指令可能已发送，但未能读取最新状态。请刷新后查看。"
                    lastAction = "状态未确认：\(binding.name)"
                }
            } catch {
                guard attempt == generation else { return }
                actionErrors[id] = friendly(error)
                lastAction = "未能执行：\(binding.name)"
            }
        }
    }

    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchAtLogin = SMAppService.mainApp.status == .enabled
            if SMAppService.mainApp.status == .requiresApproval {
                generalError = "请在系统设置的“登录项与扩展”中允许 HALink。"
            }
        } catch { generalError = "无法更改开机启动：\(error.localizedDescription)" }
    }

    func checkForUpdates() {
        guard updateState != .checking else { return }
        updateState = .checking
        let repository = Bundle.main.object(forInfoDictionaryKey: "HALinkUpdateRepository") as? String
        Task {
            do {
                let release = try await UpdateService().latestRelease(repository: repository)
                if try ReleaseVersion(release.tagName) > ReleaseVersion(currentVersion) {
                    updateState = .available(release.tagName, release.htmlURL)
                } else { updateState = .upToDate }
            } catch UpdateError.notPublished {
                updateState = .notPublished
            } catch {
                updateState = .failed(error is URLError ? "无法连接更新服务，请稍后重试。" : error.localizedDescription)
            }
        }
    }

    private func commit(_ next: Configuration) -> Bool {
        guard !loadFailed else { generalError = "配置文件读取失败，请先保留原文件并重新启动 App。"; return false }
        do {
            try configStore.save(next); config = next; generalError = nil; rebindShortcuts(); return true
        } catch { generalError = "无法保存配置：\(error.localizedDescription)"; return false }
    }
    private func friendly(_ error: Error) -> String {
        if let error = error as? URLError {
            switch error.code {
            case .timedOut: return "连接超时，请确认 Mac 和 HA 在同一网络中。"
            case .cannotFindHost, .cannotConnectToHost, .notConnectedToInternet: return "无法连接到 HA，请检查本地地址和网络。"
            case .serverCertificateUntrusted, .serverCertificateHasBadDate, .secureConnectionFailed:
                return "HTTPS 证书无法验证，请检查服务器证书或使用 HA 的本地 HTTP 地址。"
            default: return "网络连接失败，请稍后重试。"
            }
        }
        return error.localizedDescription
    }
}
