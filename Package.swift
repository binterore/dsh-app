// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DeepSeekDesktop",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "DeepSeek", targets: ["DeepSeek"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.6"),
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.20.0")
    ],
    targets: [
        .executableTarget(
            name: "DeepSeek",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "SwiftTerm", package: "SwiftTerm")
            ],
            path: "Sources"
        )
    ],
    swiftLanguageVersions: [.v5]
)
