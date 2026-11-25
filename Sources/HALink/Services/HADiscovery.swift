import Foundation
import HALinkCore
import Observation

@Observable
final class HADiscovery: NSObject, @preconcurrency NetServiceBrowserDelegate, @preconcurrency NetServiceDelegate {
    private(set) var servers: [HADiscoveredServer] = []
    private(set) var searching = false
    private(set) var message: String?
    @ObservationIgnored private var browser: NetServiceBrowser?
    @ObservationIgnored private var services: [NetService] = []
    @ObservationIgnored private var timeout: Task<Void, Never>?

    func start() {
        stop()
        servers = []; message = nil; searching = true
        let browser = NetServiceBrowser()
        self.browser = browser
        browser.delegate = self
        browser.searchForServices(ofType: "_home-assistant._tcp.", inDomain: "local.")
        timeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(8)) } catch { return }
            guard let self else { return }
            self.stop()
            if self.servers.isEmpty { self.message = "没有发现 HA。请确认在同一局域网，也可以直接填写地址。" }
        }
    }

    func stop() {
        timeout?.cancel(); timeout = nil
        browser?.stop(); browser?.delegate = nil; browser = nil
        for service in services { service.stop(); service.delegate = nil }
        services = []; searching = false
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        guard browser === self.browser, services.count < 32 else { return }
        services.append(service)
        service.delegate = self
        service.resolve(withTimeout: 5)
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        guard services.contains(where: { $0 === sender }), let host = sender.hostName else { return }
        let txt = sender.txtRecordData().map(NetService.dictionary(fromTXTRecord:)) ?? [:]
        let strings = txt.compactMapValues { String(data: $0, encoding: .utf8) }
        guard let server = try? HADiscoveredServer(name: sender.name, host: host, port: sender.port, txt: strings) else { return }
        servers.removeAll { $0.id == server.id }
        servers.append(server)
        servers.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) {
        guard browser === self.browser else { return }
        stop()
        message = "无法搜索局域网。请在系统设置中允许 HALink 访问本地网络，或手动填写地址。"
    }
}
