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

  static var allTests = [
    ("testDefaultInstancePath", testDefaultInstancePath),
  ]
}
