#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public struct Remote: CustomStringConvertible {
  
  public struct Command: CustomStringConvertible {
    public let name: String
    public let parentName: String
    private let lircInstance: LIRC
    internal init(name: String, parentName: String, lirc: LIRC) {
      self.name = name
      self.parentName = parentName
      self.lircInstance = lirc
    }

    public func send(_ type: SendType = .once, waitForReply: Bool = false) throws {
      try lircInstance.send(type, remote: parentName, command: name, waitForReply: waitForReply)
    }

    public var description: String { return name }
  }
  
  public let name: String
  public let commands: [Remote.Command]

  internal init(name: String, commands: [Remote.Command]) {
    self.name = name
    self.commands = commands
  }

  public func command(_ s: String) -> Command? {
    return self.commands.filter({ $0.name.lowercased() == s.lowercased() }).first
  }

  public var description: String { return "Remote( \(name), Commands: \(commands) )\n" }
}
