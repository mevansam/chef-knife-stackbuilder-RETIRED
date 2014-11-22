# Copyright (c) 2014 Mevan Samaratunga

require File.expand_path('../../../spec_helper', __FILE__)

include StackBuilder::Common::Helpers

describe StackBuilder::Chef do

    before(:all) do

        @logger = StackBuilder::Common::Config.logger

        @cwd = Dir.getwd

        @test_data_path = File.expand_path('../../../data', __FILE__)

        @tmp_dir = Dir.mktmpdir
        @repo_path = "#{@tmp_dir}/test_repo"

        @stack_ids = { :dev => 'DEV', :test => 'TEST', :prod => 'PROD' }

        # Get VBox to start host only network for 192.168.50.0/24
        # and set vbox host ip where chef will be reachable
        network = `VBoxManage list hostonlyifs | grep -B 3 192.168.50.1 | awk '/Name:/ { print $2 }'`.chomp

        if network.empty?
            puts 'A virtual box host only network for 192.168.50.0/24 subnet does not exist.'
            exit 1
        end

        `VBoxManage hostonlyif ipconfig #{network} --ip 192.168.50.1`

        # This requires passwordless sudo to be enabled
        `sudo ifconfig #{network} down`
        `sudo ifconfig #{network} up`
    end

    after(:all) do
        FileUtils.rm_rf(@tmp_dir)

        Dir.chdir(@cwd)
    end

    it "should upload the stack" do

        knife_cmd = Chef::Knife::StackInitializeRepo.new
        knife_cmd.config[:repo_path] = @repo_path
        knife_cmd.config[:certs] = 'wpweb.stackbuilder.org,wpdb.stackbuilder.org'
        knife_cmd.config[:envs] = 'DEV,TEST,PROD'
        knife_cmd.config[:cookbooks] = 'ohai:=2.0.1,haproxy:=1.6.6,mysql:=5.6.1,wordpress:=2.3.0'
        knife_cmd.run

        # Copy the test data into the repo
        system("cp -fr #{@test_data_path}/test_repo/* #{@repo_path}")

        knife_cmd = Chef::Knife::StackUploadRepo.new
        knife_cmd.config[:repo_path] = @repo_path
        run_knife(knife_cmd)
    end

    def validate_nodes(nodes)

        knife_cmd = Chef::Knife::NodeList.new
        node_list = run_knife(knife_cmd).split
        expect(node_list.size).to eq(nodes.size)
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

        knife_cmd = Chef::Knife::StackBuild.new
        knife_cmd.name_args = [ @test_data_path + '/test_repo/stacks/stack1.yml' ]
        knife_cmd.config[:stack_id] = @stack_ids[:dev]
        knife_cmd.config[:environment] = 'DEV'
        knife_cmd.config[:repo_path] = @repo_path
        knife_cmd.run

        validate_nodes(['database-DEV-0', 'wordpress-DEV-0', 'loadbalancer-DEV-0'])
    end

    it "should scale up the DEV stack web tier" do

        knife_cmd = Chef::Knife::StackBuild.new
        knife_cmd.name_args = [ @test_data_path + '/test_repo/stacks/stack1.yml' ]
        knife_cmd.config[:stack_id] = @stack_ids[:dev]
        knife_cmd.config[:environment] = 'DEV'
        knife_cmd.config[:node] = 'wordpress:2'
        knife_cmd.config[:repo_path] = @repo_path
        knife_cmd.run

        validate_nodes(['database-DEV-0', 'wordpress-DEV-0', 'wordpress-DEV-1', 'loadbalancer-DEV-0'])
    end

    it "should scale down the DEV stack web tier" do

        knife_cmd = Chef::Knife::StackBuild.new
        knife_cmd.name_args = [ @test_data_path + '/test_repo/stacks/stack1.yml' ]
        knife_cmd.config[:stack_id] = @stack_ids[:dev]
        knife_cmd.config[:environment] = 'DEV'
        knife_cmd.config[:node] = 'wordpress:1'
        knife_cmd.config[:repo_path] = @repo_path
        knife_cmd.run

        validate_nodes(['database-DEV-0', 'wordpress-DEV-0', 'loadbalancer-DEV-0'])
    end

    it "should destroy the DEV stack" do

        stack = StackBuilder::Stack::Stack.new(
            StackBuilder::Chef::NodeProvider.new(@repo_path, 'DEV'),
            @test_data_path + '/test_repo/stacks/stack1.yml',
            @stack_ids[:dev] )

        stack.destroy

        knife_cmd = Chef::Knife::NodeList.new
        node_list = run_knife(knife_cmd).split
        expect(node_list.empty?).to be_truthy
    end

    it "should build TEST stack" do

        knife_cmd = Chef::Knife::StackBuild.new
        knife_cmd.name_args = [ @test_data_path + '/test_repo/stacks/stack2.yml' ]
        knife_cmd.config[:stack_id] = @stack_ids[:test]
        knife_cmd.config[:environment] = 'TEST'
        knife_cmd.config[:repo_path] = @repo_path
        knife_cmd.run

        knife_cmd = Chef::Knife::NodeList.new
        node_list = run_knife(knife_cmd).split
        expect(node_list).to include('test-TEST-0')

        knife_cmd = Chef::Knife::VagrantServerList.new
        knife_cmd.config[:vagrant_dir] = File.join(Dir.home, '/.vagrant')
        server_list = run_knife(knife_cmd)
        expect(server_list.lines.keep_if { |l| l=~/test-TEST-0/ }.first.chomp.end_with?('running')).to be_truthy

        knife_cmd = Chef::Knife::Ssh.new
        knife_cmd.name_args = [ 'name:test-TEST-0', "sudo sh -c '[ -e ~/stack_configured ] && echo yes'" ]
        knife_cmd.config[:attribute] = 'ipaddress'
        knife_cmd.config[:ssh_user] = 'vagrant'
        knife_cmd.config[:identity_file] = Dir.home + '/.vagrant/insecure_key'
        result = run_knife(knife_cmd).chomp
        expect(result[/\d+\.\d+\.\d+\.\d+ (\w+)/, 1]).to eq('yes')

        knife_cmd = Chef::Knife::Ssh.new
        knife_cmd.name_args = [ 'name:test-TEST-0', "sudo sh -c 'cat /etc/chef/encrypted_data_bag_secret'" ]
        knife_cmd.config[:attribute] = 'ipaddress'
        knife_cmd.config[:ssh_user] = 'vagrant'
        knife_cmd.config[:identity_file] = Dir.home + '/.vagrant/insecure_key'
        result = run_knife(knife_cmd).chomp

        expect(result[/\d+\.\d+\.\d+\.\d+ (.*)/, 1]).to eq(IO.read("#{@repo_path}/secrets/TEST"))
    end

    it "should destroy TEST stack" do

        stack = StackBuilder::Stack::Stack.new(
            StackBuilder::Chef::NodeProvider.new(@repo_path, 'TEST'),
            @test_data_path + '/test_repo/stacks/stack2.yml',
            @stack_ids[:test] )

        stack.destroy

        knife_cmd = Chef::Knife::NodeList.new
        node_list = run_knife(knife_cmd).split
        expect(node_list).to_not include('test-TEST-0')

        knife_cmd = Chef::Knife::VagrantServerList.new
        knife_cmd.config[:vagrant_dir] = File.join(Dir.home, '/.vagrant')
        server_list = run_knife(knife_cmd)
        expect(server_list.lines.keep_if { |l| l=~/test-TEST-0/ }.empty?).to be_truthy
    end
end