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
    XCTAssertThrowsError(try netLIRCFake.listRemotes(), "Expected a Cannot Connect to Socket error", {print($0)})
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
    var messageText: String = ""
    class TestSocket : LIRCSocket {
      override func send(text: String, discardResult: Bool = true) throws -> String? {
        debugPrint(text)
        let expected = "\(testSendType.rawValue) \(testDeviceName) \(testCommandName)"
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
        try super.init()
      }
//      override func send(_ type: SendType = .once, remote: String, command: String, waitForReply: Bool = false) throws {
//        <#code#>
//      }
    }
    
    do {
      let l = try TestLIRC(testDeviceName: "TestDevice", testCommandName: "power", testSendType: .once)
      let r = Remote.Command(name: "power", parentName: "TestDevice", lirc: l)

      let socket = try l.lircSocket()
      XCTAssertTrue(type(of: socket) == TestSocket.self)
      try r.send()
      
      try l.send(.once, remote: "TestDevice", command: "power", waitForReply: false)
      
    } catch let error {
      XCTAssertNotNil((error as? LIRCError), "Error should be LIRCError")
      XCTFail()
    }
    
  }
  
  

  static var allTests = [
    ("testDefaultInstancePath", testDefaultInstancePath),
    ("testLircThrows", testLircThrows),
    ("testLircInit", testLircInit),
    ("testLIRCSocketCreate", testLIRCSocketCreate),
    ("testSocketSendMessage", testSocketSendMessage)
    
  ]
}
