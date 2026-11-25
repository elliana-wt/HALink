import Foundation

final class NoRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

public struct HAClient: Sendable {
    public let endpoint: Endpoint
    private let token: String
    private let session: URLSession
    public init(endpoint: Endpoint, token: String, session: URLSession? = nil) throws {
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, !token.contains(where: { $0.isNewline }) else { throw HAError.missingToken }
        self.endpoint = endpoint; self.token = token
        if let session { self.session = session }
        else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 10
            config.timeoutIntervalForResource = 20
            config.httpCookieStorage = nil
            config.urlCache = nil
            self.session = URLSession(configuration: config, delegate: NoRedirects(), delegateQueue: nil)
        }
    }
    public func states() async throws -> [HAEntity] {
        try decode([HAEntity].self, data: await request("states"))
    }
    public func state(_ entityID: String) async throws -> HAEntity {
        try decode(HAEntity.self, data: await request("states/" + entityID))
    }
    public func services() async throws -> Set<String> {
        struct Domain: Decodable { let domain: String; let services: [String: Ignored] }
        struct Ignored: Decodable {}
        let domains = try decode([Domain].self, data: await request("services"))
        return Set(domains.flatMap { domain in domain.services.keys.map { domain.domain + "." + $0 } })
    }
    public func perform(_ binding: DeviceBinding) async throws {
        let domain = String(binding.entityID.split(separator: ".").first ?? "")
        guard DeviceAction.candidates(for: domain).contains(binding.action) else { throw HAError.invalidResponse }
        let body = try JSONEncoder().encode(["entity_id": binding.entityID])
        _ = try await request("services/\(domain)/\(binding.action.rawValue)", method: "POST", body: body)
    }
    public func perform(_ command: HAControlRequest) async throws {
        _ = try await request("services/\(command.domain)/\(command.service)", method: "POST",
                              body: JSONEncoder().encode(command.data))
    }
    @MainActor public func realtime() -> HARealtime {
        HARealtime(endpoint: endpoint, token: token)
    }
    public func makeRequest(_ path: String, method: String = "GET", body: Data? = nil) -> URLRequest {
        var request = URLRequest(url: endpoint.api(path), cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.httpMethod = method
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        return request
    }
    private func request(_ path: String, method: String = "GET", body: Data? = nil) async throws -> Data {
        let (data, response) = try await session.data(for: makeRequest(path, method: method, body: body))
        guard let response = response as? HTTPURLResponse else { throw HAError.invalidResponse }
        switch response.statusCode {
        case 200...299: return data
        case 300...399: throw HAError.redirected
        case 401: throw HAError.unauthorized
        case 403: throw HAError.forbidden
        case 404: throw HAError.notFound
        default: throw HAError.response(response.statusCode)
        }
    }
    private func decode<T: Decodable>(_ type: T.Type, data: Data) throws -> T {
        do { return try JSONDecoder().decode(type, from: data) }
        catch { throw HAError.invalidResponse }
    }
}
