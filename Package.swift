// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "GMMKBar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "GMMKBar",
            path: "Sources/GMMKBar",
            linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("ServiceManagement")]
        )
    ]
)
