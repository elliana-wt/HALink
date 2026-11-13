import Foundation

public struct ReleaseVersion: Comparable, Equatable, Sendable {
    private let components: [Int]

    public init(_ text: String) throws {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.first == "v" || value.first == "V" { value.removeFirst() }
        value = String(value.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count), parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else {
            throw UpdateError.invalidVersion
        }
        let numbers = parts.compactMap { Int($0) }
        guard numbers.count == parts.count else { throw UpdateError.invalidVersion }
        components = numbers + Array(repeating: 0, count: 3 - numbers.count)
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.components.lexicographicallyPrecedes(rhs.components)
    }
}

public struct GitHubRelease: Decodable, Sendable {
    public let tagName: String
    public let htmlURL: URL
    enum CodingKeys: String, CodingKey { case tagName = "tag_name", htmlURL = "html_url" }
}

public enum UpdateError: LocalizedError, Equatable {
    case notPublished, invalidRepository, invalidVersion, invalidResponse, rateLimited
    public var errorDescription: String? {
        switch self {
        case .notPublished: "更新尚未发布。"
        case .invalidRepository: "更新地址无效。"
        case .invalidVersion: "无法识别发布版本，请稍后重试。"
        case .invalidResponse: "未能读取更新信息，请稍后重试。"
        case .rateLimited: "检查更新过于频繁，请稍后重试。"
        }
    }
}

public struct UpdateService: Sendable {
    private let session: URLSession
    public init(session: URLSession? = nil) {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.urlCache = nil
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 20
        self.session = session ?? URLSession(configuration: config)
    }

    public func latestRelease(repository: String?) async throws -> GitHubRelease {
        let repository = repository?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !repository.isEmpty else { throw UpdateError.notPublished }
        let parts = repository.split(separator: "/", omittingEmptySubsequences: false)
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")
        guard parts.count == 2,
              parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && $0.unicodeScalars.allSatisfy(allowed.contains) }),
              let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest") else {
            throw UpdateError.invalidRepository
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("HALink", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw UpdateError.invalidResponse }
        if response.statusCode == 404 { throw UpdateError.notPublished }
        if [403, 429].contains(response.statusCode) { throw UpdateError.rateLimited }
        guard (200..<300).contains(response.statusCode) else { throw UpdateError.invalidResponse }
        let release: GitHubRelease
        do { release = try JSONDecoder().decode(GitHubRelease.self, from: data) }
        catch { throw UpdateError.invalidResponse }
        guard release.htmlURL.scheme == "https", release.htmlURL.host == "github.com" else {
            throw UpdateError.invalidResponse
        }
        return release
    }
}
