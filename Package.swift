// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "HALink",
    platforms: [.macOS(.v26)],
    products: [.executable(name: "HALink", targets: ["HALink"])],
    targets: [
        .target(name: "HALinkCore"),
        .executableTarget(name: "HALink", dependencies: ["HALinkCore"],
                          swiftSettings: [.defaultIsolation(MainActor.self), .enableUpcomingFeature("NonisolatedNonsendingByDefault")]),
        .testTarget(name: "HALinkCoreTests", dependencies: ["HALinkCore"], exclude: ["Fixtures"]),
        .testTarget(name: "HALinkTests", dependencies: ["HALink"],
                    swiftSettings: [.defaultIsolation(MainActor.self), .enableUpcomingFeature("NonisolatedNonsendingByDefault")])
    ]
)
