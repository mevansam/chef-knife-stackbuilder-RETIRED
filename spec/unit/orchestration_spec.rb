# Copyright (c) 2012-2012 Fidelity Investents.

require File.expand_path("../../spec_helper", __FILE__)
require File.expand_path("../call_home_server", __FILE__)

describe Knife::Stackbuilder do

=begin
    def validate_system(system, scale)
        
        webserver1_host = nil
        webserver2_hosts = [ ]
        
        system.nodes.each do |k,n|
            
            if n.is_a?(Click2Compute::Orchestration::VMNode)
                
                case n.name
                    when "fileserver"
                        puts "\tfileserver: #{n.get_current_scale} = expecting 1"
                        n.get_current_scale.should eq(1)
                    when "webserver2"
                        puts "\twebserver2: #{n.get_current_scale} = expecting #{scale}"
                        n.get_current_scale.should eq(scale)
                        webserver2_hosts = n.vms.collect { |vm| vm.primary_hostname }
                    when "webserver1"
                        puts "\twebserver1: #{n.get_current_scale} = expecting 1"
                        n.get_current_scale.should eq(1)
                        webserver1_host = n.vms[0].primary_hostname
                end
            end
        end
        
        webserver1_host.should_not be_nil
        
        resp = Net::HTTP.get(webserver1_host, "/")
        expect(resp).to match(/Test Web Site 1/)
        
        host_links = (resp.split.select { |s| s[/.*http:\/\/.*"/] }).collect { |s| s[/.*http:\/\/(.*)"/,1] }
        host_uuids = (resp.split("\n").select { |s| s[/has uuid .*\./] }).collect { |s| s[/has uuid (.*)\./,1] }
        
        webserver2_hosts.size.should eq(host_links.size)
        webserver2_hosts.size.should eq(host_uuids.size)
        
        i = 0
        shared_uuid = nil
        host_links.each do |h|
            
            resp1 = Net::HTTP.get(h, "/")
            expect(resp1).to match(/Test Web Site 2/)
            expect(resp1).to match(/My UUID is #{host_uuids[i]}/)
            
            resp2 = Net::HTTP.get(h, "/shared/page.html")
            expect(resp2).to match(/Shared Content/)
            if shared_uuid.nil?
                shared_uuid = resp2[/Shared UUID is (.*)\</, 1]
            else
                expect(resp2).to match(/Shared UUID is #{shared_uuid}\</)
            end
            
            i += 1
        end
    end
    
    it "should validate a system dependency graph" do
        
        connection = $client.connection
        orchestration_pattern = File.expand_path("../../../test/system-templates/system_dependency_test.yml", __FILE__)
        system = Click2Compute::Orchestration::System.new(connection, orchestration_pattern)
        system.validate
        system.orchestrate
    end
    
    it "should recognize circular dependencies in an invalid system dependency graph" do

        expect{
            
            connection = $client.connection
            orchestration_pattern = File.expand_path("../../../test/system-templates/system_circular_dependency_test.yml", __FILE__)
            system = Click2Compute::Orchestration::System.new(connection, orchestration_pattern)
            system.validate
            system.orchestrate
            
        }.to raise_error(Click2Compute::Common::CloudError)

    end
    
    it "should build a system" do
        
        call_home_server = CallHomeServer.new( {
                "webserver1_0" => [ "create", "install", "start" ],
                "webserver2_0" => [ "create", "install", "start" ]
            } )
        
        connection = $client.connection
        orchestration_pattern = File.expand_path("../../../test/system-cookbook/system.yml", __FILE__)
        system = Click2Compute::Orchestration::System.new(connection, orchestration_pattern, nil, { 
            "attributes" => {
                "call_home" => {
                    "server" => call_home_server.host
                } 
            } 
        } )
        
        system.name.should eq("system_orchestration_test")
        system.nodes.size.should eq(5)
        system.validate
        
        call_home_server.start
        begin
            system.orchestrate
        ensure
            call_home_server.stop
        end
        
        $system_id = system.id
        puts "\nBuilt system: #{$system_id}"
    end
    
    it "should find the system just built and scale it up" do
        
        call_home_server = CallHomeServer.new( {
                "webserver1_0" => [ "create", "install", "start" ],
                "webserver2_0" => [ "create", "install", "start" ],
                "webserver2_1" => [ "create", "install", "start" ],
                "webserver2_2" => [ "create", "install", "start" ]
            } )
        
        connection = $client.connection
        orchestration_pattern = File.expand_path("../../../test/system-cookbook/system.yml", __FILE__)
        system = Click2Compute::Orchestration::System.new(connection, orchestration_pattern, $system_id, { 
            "attributes" => {
                "call_home" => {
                    "server" => call_home_server.host
                } 
            } 
        } )

        puts "\nLoaded base system: #{$system_id} => #{system.nodes}"
        validate_system(system, 1)

        call_home_server.start
        begin
            system.scale("webserver2", 3)
        ensure
            call_home_server.stop
        end
    end
    
    it "should find scaled system and reset it to the original scale and destroy it" do
        
        call_home_server = CallHomeServer.new( {
                "webserver1_0" => [ "create", "install", "start" ],
                "webserver2_0" => [ "create", "install", "start" ],
                "webserver2_1" => [ "stop", "uninstall" ],
                "webserver2_2" => [ "stop", "uninstall" ]
            } )
        
        connection = $client.connection
        orchestration_pattern = File.expand_path("../../../test/system-cookbook/system.yml", __FILE__)
        system = Click2Compute::Orchestration::System.new(connection, orchestration_pattern, $system_id, { 
            "attributes" => {
                "call_home" => {
                    "server" => call_home_server.host
                } 
            } 
        } )
        
        puts "\nLoaded system after scale up: #{$system_id} => #{system.nodes}"
        validate_system(system, 3)

        call_home_server.start
        begin
            system.reset()
        ensure
            call_home_server.stop
        end
    end
    
    it "should destroy the system and catch an error that system has been destroyed" do
        
        call_home_server = CallHomeServer.new( {
                "webserver1_0" => [ "stop", "uninstall" ],
                "webserver2_0" => [ "stop", "uninstall" ],
            } )
        
        connection = $client.connection
        orchestration_pattern = File.expand_path("../../../test/system-cookbook/system.yml", __FILE__)
        system = Click2Compute::Orchestration::System.new(connection, orchestration_pattern, $system_id, { 
            "attributes" => {
                "call_home" => {
                    "server" => call_home_server.host
                } 
            } 
        } )
        
        puts "\nLoaded system after reset: #{$system_id} => #{system.nodes}"
        validate_system(system, 1)

        call_home_server.start
        begin
            system.destroy()
        ensure
            call_home_server.stop
        end
        
        expect{
            
            connection = $client.connection
            orchestration_pattern = File.expand_path("../../../test/system-cookbook/system.yml", __FILE__)
            system = Click2Compute::Orchestration::System.new(connection, orchestration_pattern, $system_id) 
            
        }.to raise_error(Click2Compute::Common::CloudError)
    end
=end
    
end
