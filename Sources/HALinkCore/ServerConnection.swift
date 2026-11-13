import Foundation

public struct ServerConnection: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var address: String

    public init(id: UUID = UUID(), name: String, address: String) {
        self.id = id
        self.name = name
        self.address = address
    }
}

public enum ServerConfigurationError: LocalizedError, Equatable {
    case missingName, duplicateAddress, missingServer
    public var errorDescription: String? {
        switch self {
        case .missingName: "请填写服务器名称。"
        case .duplicateAddress: "这个地址已经在服务器列表中，请打开已有服务器进行设定。"
        case .missingServer: "这台服务器已被移除，请关闭窗口后重新添加。"
        }
    }
}
