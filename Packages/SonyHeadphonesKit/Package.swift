// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "SonyHeadphonesKit",
    platforms: [.macOS(.v14)],
    products: [.library(name: "SonyHeadphonesKit", targets: ["SonyHeadphonesKit"])],
    targets: [
        .target(
            name: "SonyHeadphonesKit",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.linkedFramework("IOBluetooth")]
        ),
        .testTarget(
            name: "SonyHeadphonesKitTests",
            dependencies: ["SonyHeadphonesKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
