// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DoubaoLookup",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "DoubaoLookup", targets: ["DoubaoLookup"])
    ],
    targets: [
        .executableTarget(name: "DoubaoLookup")
    ]
)
