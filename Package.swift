// swift-tools-version:4.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "SwiftLIRC",
  products: [
    .library(name: "LIRC", targets: ["LIRC"])
  ],
  dependencies: [
  ],
  targets: [
    .target(
      name: "irswend",
      dependencies: ["LIRC"],
      path: "./Sources/irswend"),
    .target(
      name: "irswreceive",
      dependencies: ["LIRC"],
      path: "./Sources/irswreceive"),
    .target(
      name: "LIRC",
      path: "./Sources/LIRC"),
    .testTarget(
      name: "LIRCTests",
      dependencies: ["LIRC"]),
  ]
)
