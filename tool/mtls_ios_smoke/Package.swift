// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TropaMtlsSmoke",
    platforms: [.iOS(.v15)],
    products: [],
    targets: [
        .binaryTarget(
            name: "HiddifyCore",
            path: "../../ios/Frameworks/HiddifyCore.xcframework"
        ),
        .testTarget(
            name: "TropaMtlsSmokeTests",
            dependencies: ["HiddifyCore"],
            path: "Tests/TropaMtlsSmokeTests",
            resources: [.copy("Fixtures")],
            linkerSettings: [
                .linkedLibrary("resolv"),
            ]
        ),
    ]
)
