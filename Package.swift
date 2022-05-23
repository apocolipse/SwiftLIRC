// swift-tools-version: 5.6
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "SwiftLIRC",
  platforms: [ .macOS(.v10_15) ],
  products: [.library(name: "LIRC", targets: ["LIRC"])],
  dependencies: [],
  targets: [.target(name: "LIRC", dependencies: []),
            .executableTarget(name: "irswend", dependencies: ["LIRC"], path: "./Sources/irswend"),
            .target(name: "irswreceive", dependencies: ["LIRC"], path: "./Sources/irswreceive"),
            .testTarget(name: "LIRCTests", dependencies: ["LIRC"])
  ]
)
