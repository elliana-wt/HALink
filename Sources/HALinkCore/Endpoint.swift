import Foundation

public struct Endpoint: Equatable, Sendable {
    public let url: URL

    public init(_ input: String) throws {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasScheme = text.contains("://")
        guard !text.isEmpty,
              var parts = URLComponents(string: hasScheme ? text : "http://" + text),
              let host = parts.host, !host.isEmpty,
              ["http", "https"].contains(parts.scheme?.lowercased() ?? ""),
              parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil,
              parts.path.isEmpty || parts.path == "/",
              !host.contains(where: { $0.isWhitespace }),
              parts.port.map({ (1...65535).contains($0) }) ?? true
        else { throw HAError.invalidAddress }
        parts.scheme = parts.scheme?.lowercased()
        parts.host = host.lowercased()
        if !hasScheme, parts.port == nil { parts.port = 8123 }
        parts.path = ""
        guard let url = parts.url else { throw HAError.invalidAddress }
        self.url = url
    }

    public func api(_ path: String) -> URL {
        url.appending(path: "api/" + path)
    }
}

public enum HAError: LocalizedError, Equatable {
    case invalidAddress, missingToken, unauthorized, forbidden, notFound, redirected
    case response(Int), invalidResponse

    public var errorDescription: String? {
        switch self {
        case .invalidAddress: "请输入 HA 的根地址，例如 http://192.168.1.10:8123，不要包含页面路径或登录信息。"
        case .missingToken: "请粘贴 Home Assistant 的长期访问令牌。"
        case .unauthorized: "Token 无效或已过期，请重新填写。"
        case .forbidden: "这个 Token 没有执行该操作的权限。"
        case .notFound: "设备或接口不存在，请刷新设备并检查 HA 地址。"
        case .redirected: "这个地址发生了重定向，请直接填写最终的 HA 地址。"
        case .response(let status): "Home Assistant 返回错误（\(status)）。请检查设备和连接后重试。"
        case .invalidResponse: "返回内容不是有效的 Home Assistant 数据，请检查地址。"
        }
    }
}
