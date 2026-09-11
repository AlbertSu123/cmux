// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CmuxHotReloadRuntime",
    platforms: [.macOS(.v14)],
    products: [.library(name: "CmuxHotReloadRuntime", type: .dynamic, targets: ["CmuxHotReloadRuntime"])],
    dependencies: [
        .package(url: "https://github.com/johnno1962/InjectionLite", revision: "20dd8459d058a6012ea156eecdeef586260ad90d")
    ],
    targets: [
        .target(name: "CmuxHotReloadRuntime", dependencies: ["InjectionLite"])
    ]
)
