// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Mesa",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Mesa", targets: ["MesaApp"])],
    targets: [
        .target(name: "MouseBridge", publicHeadersPath: "include", linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("ApplicationServices")]),
        .target(name: "MouseKit", dependencies: ["MouseBridge"]),
        .executableTarget(name: "MesaApp", dependencies: ["MouseKit"], linkerSettings: [.linkedFramework("ServiceManagement")]),
        .testTarget(name: "MouseKitTests", dependencies: ["MouseKit"])
    ]
)
