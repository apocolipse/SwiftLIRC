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
if args.count == 1 {
  switch args[0] {
  case "-h", "--help":
    print("""
  Usage: irw [socket]
     -h --help     display usage summary
     -v --version     display version
  """)
    exit(0)
  case "-v", "--version":
    print("irswreceive \(Version)")
    exit(0)
  default:
    let a = args[0].split(separator: ":")
    if a.count > 1 {
      l = LIRC(host: String(a[0]), port: Int16(String(a[1]))!)
    } else {
      l = LIRC(socketPath: args[0])
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

