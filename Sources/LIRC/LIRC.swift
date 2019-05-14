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

public enum LIRCError : LocalizedError {
  case socketError(error: String)
  case sendFailed(error: String)
  case replyTooShort(reply: String)
  case badReply(error: String)
  case badData(error: String, data: [String]?)
  case remoteNotFound(remote: String)
  case commandNotFound(command: String)
  
  var localizedDescription: String {
    switch self {
    case .socketError(let error):       return "Socket Error \(error)"
    case .sendFailed(let error):        return "Send Failed \(error)"
    case .replyTooShort(let reply):     return "Reply Too Short \(reply)"
    case .badReply(let error):          return "Bad Reply \(error)"
    case .badData(let error, let data): return "Bad Data \(error): \(data ?? [])"
    case .remoteNotFound(let remote):   return "Remote not found: \(remote)"
    case .commandNotFound(let command): return "Command not found: \(command)"
    }
  }
}

public enum SendType : String {
  case once, start, stop
}

/// LIRC is intended to be a barebones LIRC interface in Swift
/// No external Socket or networking libraries are required
/// Currently only UDP Sockets are supported, TCP support planned
/// for the future
public class LIRC {
  
  /// Path for LIRC socket, currently only UDP sockets supported
  var socketPath: String
  
  
  /// Initialize LIRC structure
  ///
  /// - Parameter socketPath: Path for LIRC socket
  public init(socketPath: String = "/var/run/lirc/lircd") {
    self.socketPath = socketPath
  }
  
  private var _allRemotes: [Remote] = []
  
  
  /// All remotes associated with this LIRC instance
  public var allRemotes: [Remote] {
    if _allRemotes.count == 0 {
      do {
        _allRemotes = try generateRemotes()
      } catch let error {
        print("Error \(error)")
      }
    }
    return _allRemotes
  }
  
  private func generateRemotes() throws -> [Remote] {
    return try listRemotes().map { remote in
      return Remote(name: remote,
                    commands: try listCommands(for: remote).map({
                      Remote.Command(name: $0, parentName: remote, lirc: self)
                    }))
    }
  }
  
  
  /// Refresh remote list
  ///
  /// - Throws: LIRCError
  public func refreshRemotes() throws {
    _allRemotes = try generateRemotes()
  }
  
  
  /// Get remote by string name
  ///
  /// - Parameter named: name of remote
  /// - Returns: Remote if found
  /// - Throws: LIRCError.remoteNotFound if remote doesn't exist.
  public func remote(named: String) throws -> Remote {
    guard let r = allRemotes.filter({$0.name.lowercased() == named.lowercased()}).first else {
      throw LIRCError.remoteNotFound(remote: named)
    }
    return r
  }
  
  /// Lists all remotes for the current LIRC instance
  ///
  /// - Returns: Array of Strings for each Remote name
  /// - Throws: LIRCError if there were any communication issues.
  func listRemotes() throws -> [String] {
    return try LIRC.socketSend("list", "", "", socketPath: socketPath, shouldRead: true)
  }
  
  
  /// List all commands for a remote for the current LIRC Instance
  ///
  /// - Parameter remote: Remote name
  /// - Returns: Array of Strings for each Command name
  /// - Throws: LIRCError if there were any communication issues.
  func listCommands(for remote: String) throws -> [String] {
    
    let c = try LIRC.socketSend("list", remote, "", socketPath: socketPath, shouldRead: true)
    return c.map({ $0.components(separatedBy: " ").last! })
  }
  
  /// Send command to current LIRC instance
  ///
  /// - Parameters:
  ///   - type: Type to send (once, start, stop)
  ///   - remote: Remote name
  ///   - command: Command Name
  ///   - waitForReply: Whether or not to wait for LIRC reply.
  ///                   If false, LIRC response errors are ignored,
  ///                   if true, LIRCError will be thrown if LIRC response has errors
  /// - Throws: LIRCError (see waitForReply)
  func send(_ type: SendType = .once, remote: String, command: String, waitForReply: Bool = false) throws {
    try LIRC.socketSend("send_\(type.rawValue)", remote, command, socketPath: socketPath, shouldRead: waitForReply)
  }
  
  /// Send LIRC Command on socket (internal)
  ///
  /// - Parameters:
  ///   - directive: LIRC directive to send
  ///   - remote: Remote name or empty
  ///   - code: Command name or empty
  ///   - socketPath: Path for Unix socket
  ///   - shouldRead: Should read response?  Returns early if false
  /// - Returns: Array of Strings if data is present in response
  /// - Throws: LIRCError if there are any communication errors or LIRC Reply errors
  @discardableResult
  private static func socketSend(_ directive: String, _ remote: String, _ code: String, socketPath: String, shouldRead: Bool = false) throws -> [String] {
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    strcpy(&addr.sun_path.0, socketPath)
    #if os(Linux)
    var fd: Int32 = socket(AF_UNIX, Int32(SOCK_STREAM.rawValue), 0)
    #else
    var fd: Int32 = socket(AF_UNIX, SOCK_STREAM, 0)
    defer { close(fd) }
    
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
    let m = "\(directive) \(remote) \(code)\n"
    var sendFlags: Int32 = 0
    #if os(Linux)
    sendFlags = Int32(MSG_NOSIGNAL)
    let sendRet = Glibc.send(fd, m, m.count, sendFlags)
    #else
    let sendRet = Darwin.send(fd, m, m.count, sendFlags)
    #endif
    if sendRet < 0 {
      throw LIRCError.sendFailed(error: "Error sending: \(String(cString: strerror(errno)))")
    }
    usleep(1000)
    
    var data: [String] = []
    
    if shouldRead {
      var dat = [CChar](repeating: 0, count: 4096)
      var recvFlags: Int32 = 0
      recvFlags |= Int32(MSG_DONTWAIT)
      recv(fd, &dat, 2048, recvFlags)
      
      let op = String(bytes: dat.map({UInt8(bitPattern: $0)}), encoding: .ascii)
      let output = op ?? ""
      
      let lines = output.components(separatedBy: "\n").filter({$0 != "" && !$0.contains("\0") })
      if lines.count >= 4 {
        if lines[0] != "BEGIN" { throw LIRCError.badReply(error: "No BEGIN: \(output)") }
        if lines[1] != "\(directive) \(remote) \(code)" { throw LIRCError.badReply(error: "Wrong reply message, expected \(m): \(output)") }
        if lines[2] != "SUCCESS" { throw LIRCError.badReply(error: "Not SUCCESS: \(output)") }
        if lines.last != "END" { throw LIRCError.badReply(error: "No END: \(output)") }
        if lines[3] == "DATA" {
          if let count = Int(lines[4]) {
            for i in 5..<min(5+count, lines.count) {
              data.append(lines[i])
            }
            if data.count < count {
              throw LIRCError.badData(error: "Expected \(count), got \(data.count)", data: data)
            }
          } else { throw LIRCError.badData(error: "Couldn't get Data count \(output)", data: nil)}
          
        } else { data.append(lines[2]) } // Good, append response message (SUCCESS)
        
      } else {
        throw LIRCError.replyTooShort(reply: output)
      }
    }
    return data
  }
}
