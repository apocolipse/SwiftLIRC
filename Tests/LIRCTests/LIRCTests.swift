import XCTest
@testable import LIRC

final class LIRCTests: XCTestCase {
  
  func testDefaultInstancePath() {
    XCTAssertEqual(LIRC().socketPath, "/var/run/lirc/lircd")
  }

  func testLircThrows() {
    let lirc = LIRC()
    let sockExists = FileManager.default.fileExists(atPath: "/var/run/lirc/lircd")
    if !sockExists {
      XCTAssertThrowsError(try lirc.listRemotes(), "Expected a Cannot Connect to Socket error")
    }
    let netLIRCFake = LIRC(host: "123.345.345.654", port: 5432)
    XCTAssertThrownError(try netLIRCFake.listRemotes(), throws: LIRCError.socketError(error: .empty))
    XCTAssertThrowsError(try netLIRCFake.listRemotes()) {
      guard let e = $0 as? LIRCError else { XCTFail(); return }
      XCTAssertEqual(e.description, "getaddrinfo 8")
    }
  }

  func testLircInit() {
    let lircPathDefault = LIRC()
    XCTAssertEqual(lircPathDefault.socketPath, "/var/run/lirc/lircd")
    XCTAssertNil(lircPathDefault.host)
    XCTAssertNil(lircPathDefault.port)

    let lircPathCustom = LIRC(socketPath: "/tmp/custom.socket")
    XCTAssertEqual(lircPathCustom.socketPath, "/tmp/custom.socket")
    XCTAssertNil(lircPathCustom.host)
    XCTAssertNil(lircPathCustom.port)

    let lircIPv4Host = LIRC(host: "127.0.0.1", port: 8765)
    XCTAssertNil(lircIPv4Host.socketPath)
    XCTAssertEqual(lircIPv4Host.host, "127.0.0.1")
    XCTAssertEqual(lircIPv4Host.port, 8765)

    let lircIPv6Host = LIRC(host: "::1", port: 8765)
    XCTAssertNil(lircIPv6Host.socketPath)
    XCTAssertEqual(lircIPv6Host.host, "::1")
    XCTAssertEqual(lircIPv6Host.port, 8765)
  }

  func testLIRCSocketCreate() {
    do {
      let lircDefaultPathSocket = try LIRCSocket()
      if case .unix(let path) = lircDefaultPathSocket.addr {
        XCTAssertTrue(type(of: path) == sockaddr_un.self)
      } else {
        XCTFail()
      }
      XCTAssertEqual(lircDefaultPathSocket.addr.size, MemoryLayout<sockaddr_un>.size)


      let lircCustomPathSocket = try LIRCSocket(path: "/tmp/custom.socket")
      if case .unix(let path) = lircCustomPathSocket.addr {
        XCTAssertTrue(type(of: path) == sockaddr_un.self)
      } else {
        XCTFail()
      }
      XCTAssertEqual(lircCustomPathSocket.addr.size, MemoryLayout<sockaddr_un>.size)

      let lircIPv4Socket = try LIRCSocket(host: "127.0.0.1", port: 8765)
      if case .ipv4(let path) = lircIPv4Socket.addr {
        XCTAssertTrue(type(of: path) == sockaddr_in.self)
      } else {
        XCTFail()
      }
      XCTAssertEqual(lircIPv4Socket.addr.size, MemoryLayout<sockaddr_in>.size)


      let lircIPv6Socket = try LIRCSocket(host: "::1", port: 8765)
      if case .ipv6(let path) = lircIPv6Socket.addr {
        XCTAssertTrue(type(of: path) == sockaddr_in6.self)
      } else {
        XCTFail()
      }
      XCTAssertEqual(lircIPv6Socket.addr.size, MemoryLayout<sockaddr_in6>.size)


    } catch let error {
      XCTAssertNotNil((error as? LIRCError), "Error should be LIRCError")
      XCTFail()
    }
  }

  func testSocketSendMessage() {

    class TestSocket : LIRCSocket {
      override func send(text: String, discardResult: Bool = true) throws -> String? {
        debugPrint(text)

        switch testSendType {
        case .count(let count):
          XCTAssertEqual(text, "\(testSendType.rawValue) \(testDeviceName) \(testCommandName) \(count)")
        default:
          XCTAssertEqual(text, "\(testSendType.rawValue) \(testDeviceName) \(testCommandName)")
        }
        return text
      }
      override func connect() throws { }
      override func close() { }
      var testDeviceName: String, testCommandName: String, testSendType: SendType
      init(testDeviceName: String, testCommandName: String, testSendType: SendType) throws {
        self.testDeviceName = testDeviceName
        self.testCommandName = testCommandName
        self.testSendType = testSendType
        try super.init()
      }
    }
    class TestLIRC : LIRC {
      override func lircSocket() throws -> LIRCSocket {
        return try TestSocket(testDeviceName: testDeviceName, testCommandName: testCommandName, testSendType: testSendType)
      }
      var testDeviceName: String, testCommandName: String, testSendType: SendType
      init(testDeviceName: String, testCommandName: String, testSendType: SendType) throws {
        self.testDeviceName = testDeviceName
        self.testCommandName = testCommandName
        self.testSendType = testSendType
        super.init()
      }
    }

    do {
      let l = try TestLIRC(testDeviceName: "TestDevice", testCommandName: "power", testSendType: .once)
      let r = Remote.Command(name: "power", parentName: "TestDevice", lirc: l)
      try r.send()

      let l2 = try TestLIRC(testDeviceName: "TestDevice", testCommandName: "power", testSendType: .count(5))
      let r2 = Remote.Command(name: "power", parentName: "TestDevice", lirc: l2)
      try r2.send(.count(5))

      let socket = try l.lircSocket()
      XCTAssertTrue(type(of: socket) == TestSocket.self)


    } catch let error {
      XCTAssertNotNil((error as? LIRCError), "Error should be LIRCError")
      XCTFail()
    }

  }
  
  func testLIRCReplyParse() {
    
    class TestSocket : LIRCSocket {
      let testReplyDict: [String: String] = [
        "not-long-enough": "testforfail",
        "no-begin": "Stuff\nAnotherThing\nThree\nTest",
        "list-good": "BEGIN\nlist-good\nSUCCESS\nDATA\n5\nRemote1\nRemote2\nRemote3\nRemote4\nRemote5\nEND",  // Good response (custom but expected directive)
        "list-bad":  "BEGIN\nlist-good\nSUCCESS\nDATA\n5\nRemote1\nRemote2\nRemote3\nRemote4\nRemote5\nEND",  // Bad resposne (custom and unexpected directive)
        "send_once":    "BEGIN\nsend_once myremote button1\nSUCCESS\nEND",                                             // Good response
        "send_oncef":   "BEGIN\nsend_once myremote2 button1\nSUCCESS\nEND",
        "send_onceff":  "BEGIN\nsend_onceff myremote button1\nERROR\nEND",
        "send_oncefff":  "BEGIN\nsend_oncefff myremote button1\nSUCCESS\nNOTNED",
        "list-badcount": "BEGIN\nlist-badcount\nSUCCESS\nDATA\n8\nRemote1\nRemote2\nRemote3\nRemote4\nRemote5\nEND",
        "list-badreplycount": "BEGIN\nlist-badreplycount\nSUCCESS\nDATA\nBADNOTNUMBER\nRemote1\nRemote2\nRemote3\nRemote4\nRemote5\nEND",
      ]
      override func connect() throws { }
      override func close() { }
      override func send(text: String, discardResult: Bool = true) throws -> String? {
        return testReplyDict[text.split(separator: " ").first?.trimmingCharacters(in: .whitespaces) ?? "nil"]
      }
    }
    class TestLIRC : LIRC {
      override func lircSocket() throws -> LIRCSocket {
        return try TestSocket()
      }

    }
    let l = TestLIRC()

    
    
    // Expecting throw, test error
    XCTAssertThrownError(try l.socketSend("not-long-enough", .empty, .empty, waitForReply: true), throws: LIRCError.badReply(error: .empty))
    XCTAssertThrownError(try l.socketSend("no-begin", .empty, .empty, waitForReply: true), throws: LIRCError.badReply(error: .empty))
    
    // Shouldn't throw
    XCTAssertNoThrow(try l.socketSend("list-good", .empty, .empty, waitForReply: true))
    
    // Check list parsed properly
    let remotes = try? l.socketSend("list-good", .empty, .empty, waitForReply: true)
    XCTAssertEqual(remotes, ["Remote1", "Remote2", "Remote3", "Remote4", "Remote5"])

    // Expecting throw, test error
    XCTAssertThrownError(try l.socketSend("list-bad", .empty, .empty, waitForReply: true), throws: LIRCError.badReply(error: .empty))
    
    // Shouldn't throw
    XCTAssertNoThrow(try l.socketSend("send_once", "myremote", "button1", waitForReply: true))
    
    // Expecting throw, test error
    // should fail due to reply not matching request
    XCTAssertThrownError(try l.socketSend("send_oncef", "myremote", "button1", waitForReply: true), throws: LIRCError.badReply(error: .empty))
   
    // Should fail due to error response
    XCTAssertThrownError(try l.socketSend("send_onceff", "myremote", "button1", waitForReply: true), throws: LIRCError.badReply(error: .empty))
    
    // Should fail due to no END
    XCTAssertThrownError(try l.socketSend("send_oncefff", "myremote", "button1", waitForReply: true), throws: LIRCError.badReply(error: .empty))
    
    // Should fail due to bad data count available
    XCTAssertThrownError(try l.socketSend("list-badcount", .empty, .empty, waitForReply: true), throws: LIRCError.badData(error: .empty, data: nil))
    
    // Should fail due to reply count not a number
    XCTAssertThrownError(try l.socketSend("list-badreplycount", .empty, .empty, waitForReply: true), throws: LIRCError.badData(error: .empty, data: nil))
  }
  
  func testRemotes() {
    class TestSocket : LIRCSocket {
      override func connect() throws { }
      override func close() { }
      override func send(text: String, discardResult: Bool = true) throws -> String? {
        switch text.trimmingCharacters(in: .whitespaces) {
        case "list":
          return "BEGIN\nlist\nSUCCESS\nDATA\n1\ntestRemote\nEND"
        case "list testRemote":
          return "BEGIN\nlist testRemote\nSUCCESS\nDATA\n5\ntestCommand\nRemote2\nRemote3\nRemote4\nRemote5\nEND"
        default:
          return text
        }
      }
    }
    class TestLIRC : LIRC {
      override func lircSocket() throws -> LIRCSocket {
        return try TestSocket()
      }
    }
    
    let l = TestLIRC()
    XCTAssertNoThrow(try l.refreshRemotes())
    XCTAssertEqual(l.allRemotes.count, 1)
    print(l.allRemotes)
    XCTAssertNoThrow(try l.remote(named: "testRemote"))
    XCTAssertThrownError(try l.remote(named: "badRemote"), throws: LIRCError.remoteNotFound(remote: .empty))
    XCTAssertNoThrow(try l.remote(named: "testRemote").command("testCommand"))
    XCTAssertThrownError(try l.remote(named: "testRemote").command("badCommand"), throws: LIRCError.commandNotFound(command: .empty))
        
  }
  

  static var allTests = [
    ("testDefaultInstancePath", testDefaultInstancePath),
    ("testLircThrows", testLircThrows),
    ("testLircInit", testLircInit),
    ("testLIRCSocketCreate", testLIRCSocketCreate),
    ("testSocketSendMessage", testSocketSendMessage),
    ("testLIRCReplyParse", testLIRCReplyParse),
    ("testRemotes", testRemotes)
    
  ]
}

extension String {
  static var empty: String = ""
}

extension XCTestCase {
  func XCTAssertThrownError<T, E: Error & Equatable>(
    _ expression: @autoclosure () throws -> T,
    throws error: E,
    _ message: @autoclosure () -> String = "",
    in file: StaticString = #file,
    line: UInt = #line
    ) {
    var thrownError: Error?
    
    XCTAssertThrowsError(try expression(), message, file: file, line: line) {
      thrownError = $0
    }
    
    XCTAssertTrue(
      thrownError is E,
      "Unexpected error type: \(type(of: thrownError))",
      file: file, line: line
    )
    
    XCTAssertEqual(
      thrownError as? E, error,
      file: file, line: line
    )
  }
}

// Just test cases, don't care about associated values
extension LIRCError : Equatable {
  static public func ==(lhs: LIRCError, rhs: LIRCError) -> Bool {
    switch lhs {
    case .socketError:        if case .socketError      = rhs { return true } else { return false }
    case .sendFailed:         if case .sendFailed       = rhs { return true } else { return false }
    case .replyTooShort:      if case .replyTooShort    = rhs { return true } else { return false }
    case .badReply:           if case .badReply         = rhs { return true } else { return false }
    case .badData:            if case .badData          = rhs { return true } else { return false }
    case .remoteNotFound:     if case .remoteNotFound   = rhs { return true } else { return false }
    case .commandNotFound:    if case .commandNotFound  = rhs { return true } else { return false }
    }
  }
}
