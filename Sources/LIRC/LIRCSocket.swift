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
  static let bind = Darwin.bind
  #else
  static let read = Glibc.read
  static let send = Glibc.send
  static let connect = Glibc.connect
  static let recv = Glibc.recv
  static let close = Glibc.close
  static let bind = Glibc.bind
  #endif
  
  static let LIRCSleep = UInt32(1000)
}

internal class LIRCSocket {
  internal enum Address {
    case ipv4(sockaddr_in)
    case ipv6(sockaddr_in6)
    case unix(sockaddr_un)
    
    internal var size: Int {
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
  
  internal let addr: Address
  
  private let sockDesc: String
  
  public init(host: String, port: Int16) throws {
    self.sockDesc = "\(host):\(port)"
    var info: UnsafeMutablePointer<addrinfo>?
    
    var status = getaddrinfo(host, String(port), nil, &info)
    if status != 0 {
      throw LIRCError.socketError(error: "getaddrinfo \(status)")
    }
    
    defer { if info != nil { freeaddrinfo(info) } }

    if info == nil { throw LIRCError.socketError(error: "Couldn't get address info") }

    #if os(Linux)
    let sock_stream = Int32(SOCK_STREAM.rawValue)
    #else
    let sock_stream = SOCK_STREAM
    #endif
    
    switch info!.pointee.ai_family {
    case  AF_INET:
      var addr = sockaddr_in()
      memcpy(&addr, info!.pointee.ai_addr, Int(MemoryLayout<sockaddr_in>.size))
      self.fd = socket(AF_INET, sock_stream, 0)
      self.addr = .ipv4(addr)
    case AF_INET6:
      var addr = sockaddr_in6()
      memcpy(&addr, info!.pointee.ai_addr, Int(MemoryLayout<sockaddr_in6>.size))
      self.fd = socket(AF_INET6, sock_stream, 0)
      self.addr = .ipv6(addr)
    default: throw LIRCError.socketError(error: "Unknown socket family \(info!.pointee.ai_family)")
    }
  }
  

  public init(path: String = "/var/run/lirc/lircd") throws {
    self.sockDesc = path
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    strcpy(&addr.sun_path.0, path)
    
    #if os(Linux)
    let sock_stream = Int32(SOCK_STREAM.rawValue)
    #else
    let sock_stream = SOCK_STREAM
    #endif

    let fd: Int32 = socket(AF_UNIX, sock_stream, 0)

    if fd == -1 { throw LIRCError.socketError(error: "Error creating socket: \(String(cString: strerror(errno)))") }
    
    self.fd = fd
    self.addr = .unix(addr)
  }
  
  deinit {
    self.close()
    //self.io?.close()
  }
  
  func connect() throws {
    try self.addr.withSockaddrPointer { saddr in
      let c = System.connect(self.fd, saddr, socklen_t(self.addr.size))
      if c < 0 {
        throw LIRCError.socketError(error: "Cannot connect to socket \(sockDesc): \(String(cString: strerror(errno)))")
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
      throw LIRCError.sendFailed(error: "Error sending to socket: \(String(cString: strerror(errno)))")
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
  func removeListener() {
    io?.close()
  }
  
  func addListener(_ closure: @escaping (String?) -> Void) throws {
    if self.io != nil { self.close() }

    // connect first
    try self.connect()
    self.io = DispatchIO(type: .stream, fileDescriptor: self.fd, queue: DispatchQueue.main, cleanupHandler: { (fd) in
      _ = System.close(fd)
    })

    self.io?.setLimit(lowWater: 23) // Broadcast is always <code>(16bytes) <repeat count>(2bytes) <button name> <remote name>, so at minimum 16+1+2+1+1+1+1=23 bytes minimum
    
    // DispatchIO internals use length of SIZE_MAX (UInt) to keep reading until EOF,
    // U/Int doesn't play nice with init(bitPattern:) on linux platforms, and unsafeBitcast warns.
    // -1 represents FFFFFFFF or FFFFFFFFFFFFFFFF on respective 32/64bit platforms, aka value of SIZE_MAX
    self.io?.read(offset: 0, length: -1, queue: DispatchQueue.main, ioHandler: { (done, data, error) in
      guard let count = data?.count, count != 0 else { return }
      let readString = data?.withUnsafeBytes(body: { (b: UnsafePointer<UInt8>) -> String? in
        
        return String(cString: b)
      })?.components(separatedBy: "\n").first?.trimmingCharacters(in: .whitespacesAndNewlines) // Seems to sometimes read a newline and junk, not sure if DispatchIO or LIRCD's broadcast, either way its annoying and doesn't match output of irw

      // will have exactly 4 components <code> <repeat count> <button name> <remote control name>
      if readString?.components(separatedBy: " ").count == 4 {
        closure(readString)
      }
    })
    #if DEBUG
    print("Listening on \(sockDesc)")
    #endif
  }
}
