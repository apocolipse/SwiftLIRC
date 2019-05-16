import Dispatch
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

import Foundation
import LIRC


func main() throws {
  let l = LIRC(host: "10.0.0.5", port: 8765)
  print(l.allRemotes)
  try l.addListener {
    print($0)
  }
}
print("starting")
try main()
dispatchMain()
