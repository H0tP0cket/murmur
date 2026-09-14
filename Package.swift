// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Oblivion",
    platforms: [.macOS("26.0")],
    products: [.executable(name: "MurMur", targets: ["Oblivion"]), .executable(name: "MurMurMeetBridge", targets: ["MeetBridge"])],
    targets: [
        .executableTarget(name: "Oblivion"),
        .executableTarget(name: "MeetBridge"),
        .testTarget(name: "OblivionTests", dependencies: ["Oblivion"])
    ],
    swiftLanguageModes: [.v5]
)
