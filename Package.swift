// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Oblivion",
    platforms: [.macOS("26.0")],
    products: [.executable(name: "Oblivion", targets: ["Oblivion"])],
    targets: [
        .executableTarget(name: "Oblivion"),
        .testTarget(name: "OblivionTests", dependencies: ["Oblivion"])
    ],
    swiftLanguageModes: [.v5]
)
