// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Enconvert",
    platforms: [
        .macOS(.v12),
        .iOS(.v15),
        .tvOS(.v15),
        .watchOS(.v8),
    ],
    products: [
        .library(
            name: "Enconvert",
            targets: ["Enconvert"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "Enconvert",
            dependencies: [],
            path: "Sources/Enconvert"
        )
    ]
)
