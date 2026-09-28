// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Glissform",
    platforms: [.macOS("15.0")],
    products: [.executable(name: "Glissform", targets: ["Glissform"])],
    targets: [
        .executableTarget(name: "Glissform", resources: [
            .copy("Resources/Iconly"),
            .copy("Resources/FeatureIcons")
        ])
    ]
)
