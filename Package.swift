// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "CodexQuotaMenu",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "CodexQuotaMenu", targets: ["CodexQuotaMenu"]),
    ],
    targets: [
        .executableTarget(name: "CodexQuotaMenu"),
        .testTarget(
            name: "CodexQuotaMenuTests",
            dependencies: ["CodexQuotaMenu"]
        ),
    ]
)
