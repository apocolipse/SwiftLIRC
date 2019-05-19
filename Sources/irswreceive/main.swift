import Dispatch
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

import Foundation
import LIRC

let Version = "0.1.0"

var l: LIRC
let args = Array(CommandLine.arguments.dropFirst())
if args.count > 1 {
  switch args[0] {
  case "-h", "--help":
    print("""
  Usage: irw [socket|host] [port]
     -h --help     display usage summary
     -v --version     display version
  """)
    exit(0)
  case "-v", "--version":
    print("irswreceive \(Version)")
    exit(0)
  default:
    let a = args[0].split(separator: ":")
    if args[0].first == "/" {
      l = LIRC(socketPath: args[0])
    } else {
      l = LIRC(host: args[0], port: args.count > 1 ? Int16(args[1])! : 8765)
    }
  }
} else {
  l = LIRC()
}

do {
  try l.addListener {
    if let s = $0 {
      print(s)
    }
  }
} catch let error {
  print(error)
  exit(1)
}

dispatchMain()

