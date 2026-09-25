// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Fluent",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Fluent",
            path: "Sources/Fluent"
        ),
    ]
)
