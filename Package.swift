// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "DissectCore", platforms: [.macOS(.v14)], products: [.library(name: "DissectCore", targets: ["DissectCore"])], targets: [.target(name: "DissectCore"), .testTarget(name: "DissectCoreTests", dependencies: ["DissectCore"])])
