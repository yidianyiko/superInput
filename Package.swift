// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "StartUpSpeechBar",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "SpeechBarDomain", targets: ["SpeechBarDomain"]),
        .library(name: "SpeechBarApplication", targets: ["SpeechBarApplication"]),
        .library(name: "SpeechBarInfrastructure", targets: ["SpeechBarInfrastructure"]),
        .executable(name: "SpeechBarApp", targets: ["SpeechBarApp"])
    ],
    dependencies: [
        .package(path: "Vendor/SwiftWhisper")
    ],
    targets: [
        .target(
            name: "SpeechBarDomain"
        ),
        .target(
            name: "SpeechBarApplication",
            dependencies: ["SpeechBarDomain"]
        ),
        .target(
            name: "SpeechBarInfrastructure",
            dependencies: [
                "SpeechBarDomain",
                .product(name: "SwiftWhisper", package: "SwiftWhisper")
            ]
        ),
        .executableTarget(
            name: "SpeechBarApp",
            dependencies: [
                "SpeechBarDomain",
                "SpeechBarApplication",
                "SpeechBarInfrastructure"
            ],
            resources: [
                .copy("Resources/HardwareBridge")
            ]
        ),
        .testTarget(
            name: "SpeechBarTests",
            dependencies: [
                "SpeechBarApp",
                "SpeechBarDomain",
                "SpeechBarApplication",
                "SpeechBarInfrastructure"
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
