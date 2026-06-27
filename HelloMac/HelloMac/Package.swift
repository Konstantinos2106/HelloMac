// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "HelloMac",
    platforms: [.macOS(.v11)],
    targets: [
        .executableTarget(
            name: "HelloMac",
            path: "Sources/HelloMac",
            resources: [
                .copy("../../Resources/Info.plist")
            ]
        )
    ]
)
