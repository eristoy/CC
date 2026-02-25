// swift-tools-version: 6.0
// AbletonBackup Package Manifest
//
// Dependencies:
//   - GRDB.swift 7.x: SQLite persistence with WAL-mode DatabasePool
//   - xxHash-Swift: Fast non-cryptographic checksums for file verification
//     NOTE: If xxHash-Swift fails to resolve (package maintenance concern flagged in
//     research), remove it and fall back to CryptoKit SHA-256 in FileCopyPipeline.

import PackageDescription

let package = Package(
    name: "AbletonBackup",
    platforms: [
        .macOS(.v13)  // macOS 13 Ventura minimum (MenuBarExtra requirement)
    ],
    products: [
        .library(
            name: "BackupEngine",
            targets: ["BackupEngine"]
        ),
        .executable(
            name: "AbletonBackupCLI",
            targets: ["AbletonBackupCLI"]
        )
    ],
    dependencies: [
        .package(
            url: "https://github.com/groue/GRDB.swift.git",
            from: "7.0.0"
        ),
        .package(
            url: "https://github.com/daisuke-t-jp/xxHash-Swift.git",
            from: "1.0.0"
        )
    ],
    targets: [
        .target(
            name: "BackupEngine",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "xxHash-Swift", package: "xxHash-Swift")
            ],
            path: "Sources/BackupEngine"
        ),
        .testTarget(
            name: "BackupEngineTests",
            dependencies: ["BackupEngine"],
            path: "Tests/BackupEngineTests"
        ),
        .executableTarget(
            name: "AbletonBackupCLI",
            dependencies: ["BackupEngine"],
            path: "Sources/AbletonBackupCLI"
        )
    ],
    swiftLanguageModes: [.v6]
)
