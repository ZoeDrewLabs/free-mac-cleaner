// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "FreeMacCleaner",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "FreeMacCleaner",
            path: "Sources/FreeMacCleaner",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
