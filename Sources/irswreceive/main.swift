import Dispatch
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

import Foundation
import LIRC

print("starting")

let l = LIRC(host: "10.0.0.5", port: 8765)
try l.addListener {
  print($0)
}

dispatchMain()

//// works
//var addr = sockaddr_un()
//addr.sun_family = sa_family_t(AF_UNIX)
//strcpy(&addr.sun_path.0, "/var/run/lirc/lircd")
//#if os(Linux)
//let fd: Int32 = socket(AF_UNIX, Int32(SOCK_STREAM.rawValue), 0)
//#else
//let fd: Int32 = socket(AF_UNIX, SOCK_STREAM, 0)
//#endif
//
//if fd == -1 { throw LIRCError.socketError(error: "Error creating socket: \(String(cString: strerror(errno)))") }
//_ = try withUnsafePointer(to: addr) { ptr in
//  try ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { ptr in
//    let c = connect(fd, ptr, socklen_t(MemoryLayout<sockaddr_un>.size))
//    if c < 0 {
//      throw LIRCError.socketError(error: "Error connecting to socket: \(String(cString: strerror(errno)))")
//    }
//  }
//}
//
//
//let io = DispatchIO(type: .stream, fileDescriptor: fd, queue: DispatchQueue.main, cleanupHandler: { (fd) in
//  close(fd)
//})
//let t = unsafeBitCast(SIZE_MAX, to: Int.self)
////  let t = 20
//io.setLimit(lowWater: 1)
//io.read(offset: 0, length: t, queue: DispatchQueue.main, ioHandler: { (done, data, error) in
//  if let readString = data?.withUnsafeBytes(body: { (b: UnsafePointer<UInt8>) -> String? in
//    return String(cString: b)
//  })?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) {
//    print(readString)
//  }
//})
////  io.activate()
