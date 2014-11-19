# Copyright (c) 2014 Mevan Samaratunga

require File.expand_path('../../../spec_helper', __FILE__)

include StackBuilder::Common::Helpers

describe StackBuilder::Chef do

    before(:all) do

        @logger = StackBuilder::Common::Config.logger

        @test_data_path = File.expand_path('../../../data', __FILE__)
        @tmp_dir = Dir.mktmpdir

        @stack_ids = { :dev => 'DEV', :test => 'TEST', :prod => 'PROD' }

        # Get VBox to start host only network for 192.168.50.0/24
        # network = `VBoxManage list hostonlyifs | grep -B 3 192.168.50.1 | awk '/Name:/ { print $2 }'`.chomp
        # `sudo ifconfig #{network} up`
    end

    after(:all) do
        FileUtils.rm_rf(@tmp_dir)
    end

    it "should upload the stack" do

        repo_path = "#{@tmp_dir}/test_repo"

        knife_cmd = Chef::Knife::StackInitializeRepo.new
        knife_cmd.name_args = [ repo_path ]
        knife_cmd.config[:certs] = 'wpweb.stackbuilder.org,wpdb.stackbuilder.org'
        knife_cmd.config[:envs] = 'DEV,TEST,PROD'
        knife_cmd.config[:cookbooks] = 'ohai:=2.0.1,haproxy:=1.6.6,mysql:=5.6.1,wordpress:=2.3.0'
        run_knife(knife_cmd)

        # Copy the test data into the repo
        system("cp -fr #{@test_data_path}/test_repo/* #{repo_path}")

        knife_cmd = Chef::Knife::StackUploadRepo.new
        knife_cmd.name_args = [ repo_path ]
        run_knife(knife_cmd)
    end

    def validate_nodes(nodes)

        knife_cmd = Chef::Knife::NodeList.new
        node_list = run_knife(knife_cmd).split
        nodes.each { |n| expect(node_list).to include(n) }

        knife_cmd = Chef::Knife::ClientList.new
        client_list = run_knife(knife_cmd).split
        nodes.each { |n| expect(client_list).to include(n) }

        knife_cmd = Chef::Knife::Status.new
        knife_cmd.config[:hide_healthy] = true
        status = run_knife(knife_cmd)
        expect(status.strip.length).to eq(0)

        nodes.each do |n|

            knife_cmd = Chef::Knife::NodeShow.new
            knife_cmd.name_args = [ n ]
            knife_cmd.config[:attribute] = 'environment'
            environment = run_knife(knife_cmd)

            expect(environment[/environment: (\w+)/, 1]).to eq('DEV')
        end

        wordpress_ips = [ ]

        nodes.each do |n|

            next if n.start_with?('database')

            knife_cmd = KnifeAttribute::Node::NodeAttributeGet.new
            knife_cmd.name_args = [ n, 'ipaddress' ]
            ip = run_knife(knife_cmd).chomp
            resp = http_fetch("http://#{ip}")
            expect(resp.code).to eq('200')

            wordpress_ips << ip if n.start_with?('wordpress')
        end

        knife_cmd = Chef::Knife::Ssh.new
        knife_cmd.name_args = [ 'name:loadbalancer-DEV-0',
            "cat /etc/haproxy/haproxy.cfg | awk '/server wordpress-DEV/ {print substr($3,0,length($3)-2)}'" ]

        knife_cmd.config[:attribute] = 'ipaddress'
        knife_cmd.config[:ssh_user] = 'vagrant'
        knife_cmd.config[:identity_file] = Dir.home + '/.vagrant/insecure_key'
        ips = run_knife(knife_cmd).lines.map.collect { |line| line[/\d+\.\d+\.\d+\.\d+ (\d+\.\d+\.\d+\.\d+)/, 1] }

        expect(wordpress_ips.sort).to eq(ips.sort)
    end

    it "should build a DEV stack" do

        stack = StackBuilder::Stack::Stack.new(
                StackBuilder::Chef::NodeProvider.new,
                @test_data_path + '/test_repo/stacks/stack1.yml',
                @stack_ids[:dev] )

        stack.orchestrate
        validate_nodes(['database-DEV-0', 'wordpress-DEV-0', 'loadbalancer-DEV-0'])
    end

    it "should scale the DEV stack web tier" do

        stack = StackBuilder::Stack::Stack.new(
                StackBuilder::Chef::NodeProvider.new,
                @test_data_path + '/test_repo/stacks/stack1.yml',
                @stack_ids[:dev] )

        stack.scale('wordpress', 2)
        validate_nodes(['database-DEV-0', 'wordpress-DEV-0', 'wordpress-DEV-1', 'loadbalancer-DEV-0'])
    end

    it "should destroy the DEV stack" do

        stack = StackBuilder::Stack::Stack.new(
                StackBuilder::Chef::NodeProvider.new,
                @test_data_path + '/test_repo/stacks/stack1.yml',
                @stack_ids[:dev] )

        stack.destroy

        knife_cmd = Chef::Knife::NodeList.new
        node_list = run_knife(knife_cmd).split
        expect(node_list.empty?).to be_truthy
    end

end