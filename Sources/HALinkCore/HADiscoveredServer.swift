import Foundation

public struct HADiscoveredServer: Identifiable, Equatable, Sendable {
    public let name: String
    public let address: String
    public let version: String?
    public var id: String { address }

    public init(name: String, host: String, port: Int, txt: [String: String]) throws {
        let advertised = [txt["internal_url"], txt["base_url"]].compactMap { $0 }
            .compactMap { try? Endpoint($0).url.absoluteString }.first
        let host = host.hasSuffix(".") ? String(host.dropLast()) : host
        let bracketed = host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host
        let fallback = try Endpoint("http://\(bracketed):\(port)").url.absoluteString
        self.address = advertised ?? fallback
        let location = txt["location_name"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = location.flatMap { $0.isEmpty ? nil : $0 } ?? name
        self.version = txt["version"]
    }
}
