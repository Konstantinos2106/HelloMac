// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "HelloMac",
    platforms: [.macOS(.v12)],
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
