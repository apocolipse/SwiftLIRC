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

public struct Remote: CustomStringConvertible {
  
  public struct Command: CustomStringConvertible {
    
    
    /// Command name
    public let name: String
    
    
    /// Parent remote name
    public let parentName: String
    
    
    /// LIRC object instance
    private let lircInstance: LIRC
    
    
    internal init(name: String, parentName: String, lirc: LIRC) {
      self.name = name
      self.parentName = parentName
      self.lircInstance = lirc
    }

    
    /// Send IR command
    ///
    /// - Parameters:
    ///   - type: Send Type (once|start|stop)
    ///   - waitForReply: If True, reply will be validated and additional errors may be thrown
    /// - Throws: LIRCError
    public func send(_ type: SendType = .once, waitForReply: Bool = false) throws {
      try lircInstance.send(type, remote: parentName, command: name, waitForReply: waitForReply)
    }

    public var description: String { return name }
  }
  
  
  /// Remote name
  public let name: String
  
  
  /// Remote commands
  public let commands: [Remote.Command]

  internal init(name: String, commands: [Remote.Command]) {
    self.name = name
    self.commands = commands
  }

  
  /// Get command by name
  ///
  /// - Parameter s: String for command name
  /// - Returns: Command if found
  /// - Throws: LIRCError.commandNotFound if command doesn't exist
  public func command(_ s: String) throws -> Command {
    guard let c = self.commands.filter({ $0.name.lowercased() == s.lowercased() }).first else {
      throw LIRCError.commandNotFound(command: s)
    }
    return c
  }

  public var description: String { return "Remote(\(name), Commands: \(commands) )\n" }
}
