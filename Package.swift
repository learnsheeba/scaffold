// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwiftChat",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        .library(name: "SwiftChatKit", targets: ["SwiftChatKit"]),
        .library(name: "SwiftChatUI", targets: ["SwiftChatUI"]),
        .executable(name: "SwiftChatServer", targets: ["SwiftChatServer"])
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.99.0")
    ],
    targets: [
        .target(
            name: "SwiftChatKit"
        ),
        .target(
            name: "SwiftChatUI",
            dependencies: ["SwiftChatKit"]
        ),
        .executableTarget(
            name: "SwiftChatServer",
            dependencies: [
                // NOTE: the server intentionally does NOT depend on SwiftChatKit's
                // Crypto — it only routes opaque envelopes and must never decrypt.
                .product(name: "Vapor", package: "vapor")
            ]
        ),
        .testTarget(
            name: "SwiftChatKitTests",
            dependencies: ["SwiftChatKit"]
        )
    ]
)
