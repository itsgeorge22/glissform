// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Glissform",
    platforms: [.macOS("15.0")],
    products: [.executable(name: "Glissform", targets: ["Glissform"])],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")
    ],
    targets: [
        .executableTarget(name: "Glissform", dependencies: [
            .product(name: "Sparkle", package: "Sparkle")
        ], resources: [
            .copy("Resources/Iconly"),
            .copy("Resources/FeatureIcons"),
            .copy("Resources/BlurPreviews")
        ])
    ]
)
