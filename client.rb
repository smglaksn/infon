require 'socket'
TCPSocket.open(ARGV[0] || 'localhost', 1234) { |socket|
    class << socket
        alias_method  :orig_read, :read 
        attr_accessor :traffic

        def read(x)
            @traffic += x
            orig_read(x)
        end
       
        def read8
            read(1)[0]
        end

        def read16
            ret  = read8
            ret |= read8 << 7 if ret & 0x80 != 0 
            ret
        end

        def read32
            read(4).unpack("N")[0]
        end

        def readXX(len)
            read(len).unpack("A*")[0]
        end
    end

    socket.traffic = 0

    Thread.start do 
        last = socket.traffic
        loop do
            puts "TRAFFIC: % dbyte/sec" % [socket.traffic - last]
            last = socket.traffic
            sleep 1
        end
    end

    loop do 
        len = socket.read8
        print "len=%3d " % len
        case type = socket.read8
        when 0:
            print "player upd: "
            print "pno=%d "   % socket.read8
            print "mask=%d "  % mask = socket.read8
            print "alive=%s " % [socket.read8.zero? ? "quit" : "joined"]  if mask &  1 != 0
            print "name=%s  " % socket.readXX(socket.read8)               if mask &  2 != 0
            print "color=%d " % socket.read8                              if mask &  4 != 0
            print "cpu=%d "   % socket.read8                              if mask &  8 != 0
            print "score=%d " % (socket.read16 - 500)                     if mask & 16 != 0
            puts
        when 1:
            puts  "%d, %d => %d (%d) " % [socket.read8, socket.read8, socket.read8, socket.read8]
        when 2:
            puts  "msg: %s  " % socket.readXX(len)
        when 3: 
            print "creature upd: "
            print "cno=%d "         % socket.read16
            print "mask=%d "        % mask = socket.read8
            if mask &  1 != 0            
                print "alive=%s "   % [socket.read8 == 0xFF ? 
                                       "dead" : 
                                       "spawned %d,%d" % [socket.read16, socket.read16] ]
            end
            print "type=%d "        % socket.read8                      if mask &  2 != 0
            if mask & 4 != 0
                fh = socket.read8
                print "food=%d, health=%d " % [ fh >> 4, fh & 0x0F ]
            end
            print "state=%d "       % socket.read8                      if mask &  8 != 0
            print "path=%d,%d "     % [socket.read16, socket.read16]    if mask & 16 != 0
            print "target=%d "      % socket.read16                     if mask & 32 != 0
            print "message=%s "     % socket.readXX(socket.read8)       if mask & 64 != 0
            print "speed=%d "       % socket.read8                      if mask &128 != 0
            puts
        when 4:
            puts  "quit msg: %s  "  % socket.readXX(len)
            break
        when 5:
            puts  "king: %d  "      % socket.read8
        when 32:
            socket.write("guiclient\n")
            puts  "welcome: %s"     % socket.read(len).delete("\n").strip
        when 255:
            puts  "server protocol version %d" % socket.read8
        else
            puts  "???: unknown packet type #{type}"
            socket.readXX(len)
        end
    end
}
