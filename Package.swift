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
        .library(name: "MemoryDomain", targets: ["MemoryDomain"]),
        .library(name: "MemoryCore", targets: ["MemoryCore"]),
        .library(name: "MemoryExtraction", targets: ["MemoryExtraction"]),
        .library(name: "MemoryStorageSQLite", targets: ["MemoryStorageSQLite"]),
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
            name: "MemoryDomain"
        ),
        .target(
            name: "MemoryExtraction",
            dependencies: ["MemoryDomain"]
        ),
        .target(
            name: "MemoryStorageSQLite",
            dependencies: ["MemoryDomain"]
        ),
        .target(
            name: "MemoryCore",
            dependencies: ["MemoryDomain", "MemoryExtraction", "MemoryStorageSQLite"]
        ),
        .target(
            name: "SpeechBarApplication",
            dependencies: ["SpeechBarDomain", "MemoryDomain", "MemoryCore"]
        ),
        .target(
            name: "SpeechBarInfrastructure",
            dependencies: [
                "SpeechBarDomain",
                "MemoryDomain",
                .product(name: "SwiftWhisper", package: "SwiftWhisper")
            ]
        ),
        .executableTarget(
            name: "SpeechBarApp",
            dependencies: [
                "SpeechBarDomain",
                "SpeechBarApplication",
                "SpeechBarInfrastructure",
                "MemoryDomain",
                "MemoryCore",
                "MemoryExtraction",
                "MemoryStorageSQLite"
            ],
            resources: [
                .copy("Resources/HardwareBridge")
            ]
        ),
        .testTarget(
            name: "MemoryTests",
            dependencies: [
                "MemoryDomain",
                "MemoryCore",
                "MemoryExtraction",
                "MemoryStorageSQLite",
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
                "SpeechBarInfrastructure",
                "MemoryDomain",
                "MemoryCore"
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
