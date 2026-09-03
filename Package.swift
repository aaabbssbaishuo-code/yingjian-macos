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
            dependencies: [
                "SherpaOnnx"
            ],
            path: "Sources/QuickLensTranslator",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .target(
            name: "SherpaOnnx",
            dependencies: ["SherpaOnnxMacOSRuntime"],
            path: "Vendor/SherpaOnnx",
            exclude: ["LICENSE"],
            sources: ["SherpaOnnx.swift"],
            linkerSettings: [
                .linkedLibrary("c++")
            ]
        ),
        .binaryTarget(
            name: "SherpaOnnxMacOSRuntime",
            url: "https://github.com/k2-fsa/sherpa-onnx/releases/download/xcframework/sherpa-onnx-v1.13.6-macos-shared-onnxruntime-static.xcframework.zip",
            checksum: "bf2c9f847eade6d8180b13cf362df477751c55894447aa1972a505b1559add86"
        ),
        .testTarget(
            name: "QuickLensTranslatorTests",
            dependencies: ["QuickLensTranslator"],
            path: "Tests/QuickLensTranslatorTests"
        )
    ]
)
