// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FADriverKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "FADriverKit", targets: ["FADriverKit"]),
    ],
    targets: [
        .target(
            name: "FADriverKit",
            path: "Sources/FADriverKit"
        ),
        .testTarget(
            name: "FADriverKitTests",
            dependencies: ["FADriverKit"],
            path: "Tests/FADriverKitTests"
        ),
    ]
)
