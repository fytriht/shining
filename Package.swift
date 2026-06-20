// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Shining",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .executable(name: "Shining", targets: ["Shining"])
    ],
    targets: [
        .target(
            name: "ShiningCore",
            path: "Sources/ShiningCore"
        ),
        .executableTarget(
            name: "Shining",
            dependencies: ["ShiningCore"],
            path: "Sources/Shining"
        ),
        .testTarget(
            name: "ShiningTests",
            dependencies: ["ShiningCore"],
            path: "Tests/ShiningTests"
        )
    ],
    swiftLanguageModes: [.v5]
)
