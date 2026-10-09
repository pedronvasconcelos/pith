// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Pith",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "Pith",
            path: "Sources/Pith",
            swiftSettings: [.swiftLanguageMode(.v5), .enableUpcomingFeature("BareSlashRegexLiterals")]
        )
    ]
)
