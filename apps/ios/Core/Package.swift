// swift-tools-version: 5.9
// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import PackageDescription

let package = Package(
    name: "GridSpaceCore",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [.library(name: "GridSpaceCore", targets: ["GridSpaceCore"])],
    targets: [
        .target(name: "GridSpaceCore"),
        .testTarget(name: "GridSpaceCoreTests", dependencies: ["GridSpaceCore"]),
    ],
    swiftLanguageVersions: [.v5]
)
