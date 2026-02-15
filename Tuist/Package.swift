// swift-tools-version: 6.0
import PackageDescription

#if TUIST
import ProjectDescription

let packageSettings = PackageSettings(
    productTypes: [:]
)
#endif

let package = Package(
    name: "Moonlight",
    dependencies: [
        .package(url: "https://github.com/apple/swift-certificates.git", from: "1.7.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "4.2.0"),
    ]
)
