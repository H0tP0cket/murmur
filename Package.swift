// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Oblivion",
    platforms: [.macOS("26.0")],
    products: [.executable(name: "murmur", targets: ["Oblivion"]), .executable(name: "MurMurMeetBridge", targets: ["MeetBridge"])],
    targets: [
        .target(name: "CSpeexDSP", exclude: ["README.md"], publicHeadersPath: "include", cSettings: [.define("FLOATING_POINT"), .define("USE_SMALLFT"), .define("EXPORT", to: "")]),
        .executableTarget(name: "Oblivion", dependencies: ["CSpeexDSP"]),
        .executableTarget(name: "MeetBridge"),
        .testTarget(name: "OblivionTests", dependencies: ["Oblivion"])
    ],
    swiftLanguageModes: [.v5]
)
