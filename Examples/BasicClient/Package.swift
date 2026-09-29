// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BasicClient",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../../Packages/FADriverKit"),
    ],
    targets: [
        .executableTarget(
            name: "BasicClient",
            dependencies: [
                .product(name: "FADriverKit", package: "FADriverKit"),
            ],
            path: "Sources/BasicClient"
        ),
    ]
)
