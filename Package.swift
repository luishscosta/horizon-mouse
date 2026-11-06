// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "HorizonMouse",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "HorizonMouse", targets: ["HorizonMouseApp"])],
    targets: [
        .target(name: "MouseBridge", publicHeadersPath: "include", linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("ApplicationServices")]),
        .target(name: "MouseKit", dependencies: ["MouseBridge"]),
        .executableTarget(name: "HorizonMouseApp", dependencies: ["MouseKit"], linkerSettings: [.linkedFramework("ServiceManagement")]),
        .testTarget(name: "MouseKitTests", dependencies: ["MouseKit"])
    ]
)
