/*
 SwiftLIRC
 Copyright (c) 2019 Chris Simpson
 Licensed under the MIT license, as follows:
 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:
 The above copyright notice and this permission notice shall be included in all
 copies or substantial portions of the Software.
 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 SOFTWARE.)
 */

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

import Foundation
import Dispatch

struct System {
  #if canImport(Darwin)
  static let read = Darwin.read
  static let send = Darwin.send
  static let connect = Darwin.connect
  static let recv = Darwin.recv
  static let close = Darwin.close
  
  #else
  static let read = Glibc.read
  static let send = Glibc.send
  static let connect = Glibc.connect
  static let recv = Glibc.recv
  static let close = Glibc.close
  
  #endif
  
  static let LIRCSleep = UInt32(1000)
}

internal class LIRCSocket {
  private enum Address {
    case ipv4(sockaddr_in)
    case ipv6(sockaddr_in6)
    case unix(sockaddr_un)
    
    var size: Int {
      switch self {
      case .ipv4( _): return MemoryLayout<(sockaddr_in)>.size
      case .ipv6( _): return MemoryLayout<(sockaddr_in6)>.size
      case .unix( _): return MemoryLayout<(sockaddr_un)>.size
      }
    }
    
    private static func addrToSockaddr<T>(addr: T, size: Int, closure: (UnsafePointer<sockaddr>) throws -> (Void)) rethrows {
      var a = addr
      _ = try withUnsafePointer(to: &a) { ptr in
        try ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { ptr in
          try closure(ptr)
        }
      }
    }
 
    func withSockaddrPointer(closure: (UnsafePointer<sockaddr>) throws -> Void) rethrows {
      switch self {
      case .ipv4(let addr): return try Address.addrToSockaddr(addr: addr, size: size, closure: closure)
      case .ipv6(let addr): return try Address.addrToSockaddr(addr: addr, size: size, closure: closure)
      case .unix(let addr): return try Address.addrToSockaddr(addr: addr, size: size, closure: closure)
      }
    }
  }
  
  public private(set) var fd: Int32
  
  private let addr: Address
  
  public init(host: String, port: Int16) throws {
    self.fd = 0
    
    var info: UnsafeMutablePointer<addrinfo>?
    
    var status = getaddrinfo(host, String(port), nil, &info)
    if status != 0 {
      throw LIRCError.socketError(error: "getaddrinfo \(status)")
    }
    
    defer { if info != nil { freeaddrinfo(info) } }

    if info == nil { throw LIRCError.socketError(error: "Couldn't get address info") }

    print(info!.pointee.ai_addr.pointee)
    print(info!.pointee.ai_next.pointee)
    
    
    switch info!.pointee.ai_family {
    case  AF_INET:
      var addr = sockaddr_in()
      memcpy(&addr, info!.pointee.ai_addr, Int(MemoryLayout<sockaddr_in>.size))
      self.addr = .ipv4(addr)
    case AF_INET6:
      var addr = sockaddr_in6()
      memcpy(&addr, info!.pointee.ai_addr, Int(MemoryLayout<sockaddr_in6>.size))
      self.addr = .ipv6(addr)
    default: throw LIRCError.socketError(error: "Unknown socket family \(info!.pointee.ai_family)")
    }
  }
  
  public init(path: String = "/var/run/lirc/lircd") throws {
    
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    strcpy(&addr.sun_path.0, path)
    
    #if os(Linux)
    let fd: Int32 = socket(AF_UNIX, Int32(SOCK_STREAM.rawValue), 0)
    #else
    let fd: Int32 = socket(AF_UNIX, SOCK_STREAM, 0)
    #endif
    if fd == -1 { throw LIRCError.socketError(error: "Error creating socket: \(String(cString: strerror(errno)))") }
    
    self.fd = fd
    self.addr = .unix(addr)
  }
  
  deinit {
    self.close()
  }
  
  func connect() throws {
    try self.addr.withSockaddrPointer { saddr in
      let c = System.connect(self.fd, saddr, socklen_t(self.addr.size))
      if c < 0 {
        throw LIRCError.socketError(error: "Error connecting to socket: \(String(cString: strerror(errno)))")
      }
    }
  }
  
  func close() {
    self.io?.close()
    self.io = nil
    _ = System.close(self.fd)
  }
  
  @discardableResult
  func send(text: String, discardResult: Bool = true) throws-> String? {
    // connect first
    try self.connect()
    
    // Text must be newline truncated, so lets strip and re-add a newline
    let textToSend = text.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    
    #if os(Linux)
    let s = System.send(self.fd, textToSend, textToSend.count, Int32(MSG_NOSIGNAL))
    #else
    let s = System.send(self.fd, textToSend, textToSend.count, 0)
    #endif
    
    if s < 0 {
      throw LIRCError.sendFailed(error: "Error sending: \(String(cString: strerror(errno)))")
    }
    var output: String?
    if !discardResult {
      usleep(System.LIRCSleep)  // Need to sleep to read properly
      var dat = [CChar](repeating: 0, count: 4096)
      let r = System.recv(fd, &dat, dat.count, Int32(MSG_DONTWAIT))
      if r < 0 {
        throw LIRCError.sendFailed(error: "Error receiving: \(String(cString: strerror(errno)))")
      }
      output = String(bytes: dat.map({UInt8(bitPattern: $0)}), encoding: .ascii)
    }
    
    // cleanup
    self.close()
    return output
  }
  
  private var io: DispatchIO?
  
  func addListener(_ closure: @escaping (String?) -> Void) throws {
    if self.io != nil { self.close() }

    // connect first
    try self.connect()
    self.io = DispatchIO(type: .stream, fileDescriptor: self.fd, queue: DispatchQueue.main, cleanupHandler: { (fd) in
      _ = System.close(fd)
    })

    self.io?.setLimit(lowWater: 1)
    // This warns that it can be replaced with Int(bitpattern: SIZE_MAX), but that breaks on RasPi, so ignore it
    self.io?.read(offset: 0, length: unsafeBitCast(SIZE_MAX, to: Int.self), queue: DispatchQueue.main, ioHandler: { (done, data, error) in
      let readString = data?.withUnsafeBytes(body: { (b: UnsafePointer<UInt8>) -> String? in
        return String(cString: b)
      })?.trimmingCharacters(in: .whitespacesAndNewlines)
      
      closure(readString)
    })
    self.io?.activate()
  }
}
