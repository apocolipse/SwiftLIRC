import LIRC

func main() throws {
  let args = CommandLine.arguments.dropFirst()
  guard args.count > 0 else {
    print("irswend: not enough arguments")
    return
  }
  
  if args.count == 1 {
    if (args.first == "-h" || args.first == "--help") {
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
    if (args.first == "-v" || args.first == "--version") {
      print("irswend 0.1.0")
    }
  }
  
  
  
  
  
}



try main()
