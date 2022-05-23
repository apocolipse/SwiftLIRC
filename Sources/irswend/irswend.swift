import LIRC

@main
struct App {
  static func main() async throws {
    let args = CommandLine.arguments.dropFirst()
    guard args.count > 0 else {
      print("irswend: not enough arguments")
      return
    }

    switch args.count {
    case 1:
      switch args.first {
      case "-h", "--help":    printHelp()
      case "-v", "--version": printVersion()
      default:  print("irswend: not enough arguments")
      }
    case 3:
      switch args.first?.lowercased() {
      case "list":
        if args[args.startIndex + 1] == "" {
          // lis remotes
          try LIRC().allRemotes.forEach {
            print($0.name)
          }
        } else {
          print("listing \(args[args.startIndex + 1])")
          if let remote = try? LIRC().remote(named: args[args.startIndex + 1]) {
            print(remote.commands)
          } else {
            print("Unknown remote: \(args[args.startIndex + 1])")
          }
        }
      default: print("Unknown directive: \(args.first!)")
      }
    default:  print("irswend: not enough arguments")
    }
    print(args)
  }

  private static func printHelp() {
    print("""
      Synopsis:
          irswend [options] SEND_ONCE remote code [code...]
          irswend [options] SEND_START remote code
          irswend [options] SEND_STOP remote code
          irswend [options] LIST remote
          irswend [options] SET_TRANSMITTERS remote num [num...]  (TODO)
          irswend [options] SIMULATE "scancode repeat keysym remote"  (TODO)
      Options:
          -h --help                 display usage summary
          -v --version              display version
          -d --device=device        use given lircd socket [/var/run/lirc/lircd] (TODO)
          -a --address=host[:port]  connect to lircd at this address (TODO)
          -# --count=n              send command n times (TODO)

      """)
  }

  private static func printVersion() {
    print("irswend 0.1.1")
  }
}
