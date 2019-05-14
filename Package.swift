// swift-tools-version:4.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "SwiftLIRC",
  products: [
    .executable(name: "irswend", targets: ["irswend"]),
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
      name: "LIRC",
      path: "./Sources/LIRC"),
  ]
)
