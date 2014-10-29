# Copyright (c) 2014 Mevan Samaratunga

class CallHomeServer
    
    def initialize(validation)
        @@home_ip ||= UDPSocket.open { |s| s.connect("64.233.187.99", 1); s.addr.last }
        @test_server_pid = nil
        @call_home_validation = validation
    end
    
    def host
        return "http://#{@@home_ip}:8888"
    end
    
    def start
        @test_server_pid = Process.fork {
            callHomeServer = HttpServer.new(self, 8888, @@home_ip)
            callHomeServer.start
            callHomeServer.join
        }
    end
    
    def stop
        puts "Stopping Call Home Server PID #{@test_server_pid}..."
        system("kill -9 #{@test_server_pid}") unless @test_server_pid.nil?
        
        @test_server_pid = nil
        @call_home_validation = { }
    end

    # Handlers HttpServer callbacks
    
    def request_handler(request, response)
        
        req_data = request.path.split(/\//)
        host = req_data[1]
        server = req_data[2]
        event = req_data[3]
        
        assertions = @call_home_validation[server]
        
        if assertions.nil? || assertions.size == 0
            raise(Exception, "No assertion events to match")
        end
        
        assertion_event = assertions.slice!(0) 
        if assertion_event != event
            raise(Exception, "Expecting event \"#{event}\" but next event in list was \"#{assertion_event}\"")
        end
        
        @call_home_validation.delete(server) if assertions.empty?
        
        puts "Validated call home data: host=#{host}, server=#{server}, event=#{event}, events remaining=#{assertions}"
        
    rescue Exception => msg
        puts "Validation of call home data failed: host=#{host}, server=#{server}, event=#{event}"
        puts("Error: Event call back assertion failed: #{msg}")
        puts(msg.backtrace.join("\n\t"))
    end
    
    def ip_auth_handler(io)
        return true
    end
end
