import Dispatch
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

import Foundation



func main() throws {
  var addr = sockaddr_un()
  addr.sun_family = sa_family_t(AF_UNIX)
  strcpy(&addr.sun_path.0, "/var/run/lirc/lircd")
  #if os(Linux)
  var fd: Int32 = socket(AF_UNIX, Int32(SOCK_STREAM.rawValue), 0)
  #else
  var fd: Int32 = socket(AF_UNIX, SOCK_STREAM, 0)
  #endif
  
  if fd == -1 { throw LIRCError.socketError(error: "Error creating socket: \(String(cString: strerror(errno)))") }
  _ = try withUnsafePointer(to: addr) { ptr in
    try ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { ptr in
      let c = connect(fd, ptr, socklen_t(MemoryLayout<sockaddr_un>.size))
      if c < 0 {
        throw LIRCError.socketError(error: "Error connecting to socket: \(String(cString: strerror(errno)))")
      }
    }
  }
  
  
  let io = DispatchIO(type: .stream, fileDescriptor: fd, queue: DispatchQueue.main, cleanupHandler: { (fd) in
    close(fd)
  })
  io.read(offset: 0, length: Int(bitPattern: SIZE_MAX), queue: DispatchQueue.main, ioHandler: { (done, data, error) in
    let readString = data?.withUnsafeBytes(body: { (b: UnsafePointer<UInt8>) -> String? in
      return String(cString: b)
    })
    print(readString)
  })
  
}

try main()
