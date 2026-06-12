// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "QuickLensTranslator",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(
            name: "QuickLensTranslator",
            targets: ["QuickLensTranslator"]
        )
    ],
    targets: [
        .executableTarget(
            name: "QuickLensTranslator",
            path: "Sources/QuickLensTranslator",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
