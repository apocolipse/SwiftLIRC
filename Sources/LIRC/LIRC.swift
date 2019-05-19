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


public enum LIRCError : Error, CustomStringConvertible {
  case socketError(error: String)
  case sendFailed(error: String)
  case replyTooShort(reply: String)
  case badReply(error: String)
  case badData(error: String, data: [String]?)
  case remoteNotFound(remote: String)
  case commandNotFound(command: String)
  
  public var description: String {
    switch self {
    case .socketError(let error):       return "\(error)"
    case .sendFailed(let error):        return "Send Failed \(error)"
    case .replyTooShort(let reply):     return "Reply Too Short \(reply)"
    case .badReply(let error):          return "Bad Reply \(error)"
    case .badData(let error, let data): return "Bad Data \(error): \(data ?? [])"
    case .remoteNotFound(let remote):   return "Remote not found: \(remote)"
    case .commandNotFound(let command): return "Command not found: \(command)"
    }
  }
}

public enum SendType {
  case once
  case start
  case stop
  case count(Int)
  
  public init?(rawValue: String)  {
    if let i = Int(rawValue) {
      self = .count(i)
    }
    switch rawValue {
    case "send_once":   self = .once
    case "send_start":  self = .start
    case "send_stop":   self = .stop
    default: return nil
    }
  }
  public var rawValue: String {
    switch self {
    case .once:     return "send_once"
    case .start:    return "send_start"
    case .stop:     return "send_stop"
    case .count(_): return "send_once"
    }
  }
}



/// LIRC is intended to be a barebones LIRC interface in Swift
/// No external Socket or networking libraries are required
/// Currently only UDP Sockets are supported, TCP support planned
/// for the future
public class LIRC {
  
  /// Path for LIRC socket, currently only UDP sockets supported
  var socketPath: String?
  var host: String?
  var port: Int16?


  /// Init with parameters for a UNIX socket
  ///
  /// - Parameter socketPath: Path for LIRC socket
  public init(socketPath: String = "/var/run/lirc/lircd") {
    self.socketPath = socketPath
  }
 
  
  /// Init with parameters for a TCP socket
  ///
  /// - Parameters:
  ///   - host: Host to connect to (IPv4 and IPv6 are supported by this library, but lircd currently only supports IPv4 for now)
  ///   - port: Port to connect to
  public init(host: String, port: Int16) {
    self.host = host
    self.port = port
  }
  
  
  /// Get LIRCSocket based on configuration
  ///
  /// - Returns: LIRC Socket
  /// - Throws: LIRCError if theres any issues creating the socket.
  internal func lircSocket() throws -> LIRCSocket {
    if socketPath != nil {
      return try LIRCSocket(path: socketPath!)
    } else {
      return try LIRCSocket(host: host!, port: port!)
    }
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
    return try socketSend("list", "", "", waitForReply: true)
  }
  
  
  /// List all commands for a remote for the current LIRC Instance
  ///
  /// - Parameter remote: Remote name
  /// - Returns: Array of Strings for each Command name
  /// - Throws: LIRCError if there were any communication issues.
  func listCommands(for remote: String) throws -> [String] {
    
    let c = try socketSend("list", remote, "", waitForReply: true)
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
    var count = 0
    if case let .count(i) = type { count = i }
    try socketSend("\(type.rawValue)", remote, command, count: count, waitForReply: waitForReply)
  }

  
  
  @discardableResult
  private func socketSend(_ directive: String, _ remote: String, _ code: String, count: Int = 0, waitForReply: Bool = false) throws -> [String] {
    let s = try lircSocket()
    
    var data: [String] = []
    
    let message = "\(directive) \(remote) \(code)" + ((count > 0) ? " \(count)" : "")
    if !waitForReply { try s.send(text: message, discardResult: !waitForReply) }
    if waitForReply == true,
       let output = try s.send(text: message, discardResult: !waitForReply) {
      
        let lines = output.components(separatedBy: "\n").filter({$0 != "" && !$0.contains("\0") })
        if lines.count >= 4 {
          if lines[0] != "BEGIN" { throw LIRCError.badReply(error: "No BEGIN: \(output)") }
          if lines[1].trimmingCharacters(in: .whitespacesAndNewlines) != "\(directive) \(remote) \(code)".trimmingCharacters(in: .whitespacesAndNewlines) {
            throw LIRCError.badReply(error: "Wrong reply message, expected \(message): \(output)")
          }
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
      }
    }
    return data
  }
  
  private var listeners: [LIRCSocket] = []
  
  public func addListener(_ closure: @escaping (String?) -> Void) throws {
    let s = try lircSocket()
    try s.addListener(closure)
    listeners.append(s)
  }
  
  public func removeAllListeners() {
    self.listeners.removeAll()
  }
  
  deinit {
    removeAllListeners()
  }
}
