// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "KundidaToolbox",
    defaultLocalization: "de",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Selbstaktualisierung wie bei Forseti (Developer-ID-Distribution).
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
    ],
    targets: [
        .executableTarget(
            name: "KundidaToolbox",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/KundidaToolbox"
        )
    ]
)
