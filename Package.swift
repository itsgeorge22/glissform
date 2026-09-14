// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Glissform",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Glissform", targets: ["Glissform"])],
    targets: [
        .executableTarget(name: "Glissform")
    ]
)
