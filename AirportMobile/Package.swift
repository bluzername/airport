// swift-tools-version: 5.9
import PackageDescription

// Note: This Package.swift is for reference/CI builds.
// The primary build system is Xcode with the .xcodeproj.
// This app has zero external dependencies — all Apple frameworks.

let package = Package(
    name: "AirportMobile",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "AirportMobile", targets: ["AirportMobile"]),
    ],
    targets: [
        .target(
            name: "AirportMobile",
            path: "AirportMobile"
        ),
    ]
)
