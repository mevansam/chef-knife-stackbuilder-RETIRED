# Copyright (c) 2014 Mevan Samaratunga

require File.expand_path('../../../spec_helper', __FILE__)

include StackBuilder::Common::Helpers

describe StackBuilder::Chef do

    # Change the following to true if you want to create
    # the repo in your ~/tmp folder for debugging
    INTERACTIVE_DEBUG_MODE = false

    # Comment the tests below to make the test
    # run shorter when debugging issues
    RUN_TESTS = [
        :wordpress,
        :generic,
        :containter
    ]

    before(:all) do

        @logger = StackBuilder::Common::Config.logger

        @cwd = Dir.getwd

        @test_data_path = File.expand_path('../../../data', __FILE__)

        @tmp_dir = INTERACTIVE_DEBUG_MODE ? Dir.home + '/tmp' : Dir.mktmpdir
        @repo_path = "#{@tmp_dir}/test_repo"

        @stack_ids = { :dev => 'DEV', :test => 'TEST', :prod => 'PROD' }

        # Get VBox to start host only network for 192.168.50.0/24
        # and set vbox host ip where chef will be reachable
        # network = `VBoxManage list hostonlyifs | grep -B 3 192.168.50.1 | awk '/Name:/ { print $2 }'`.chomp
        #
        # if network.empty?
        #     puts 'A virtual box host only network for 192.168.50.0/24 subnet does not exist.'
        #     exit 1
        # end
        #
        # `VBoxManage hostonlyif ipconfig #{network} --ip 192.168.50.1`

        # This requires passwordless sudo to be enabled
        # `sudo ifconfig #{network} down`
        # `sudo ifconfig #{network} up`
    end

    after(:all) do
        FileUtils.rm_rf(@tmp_dir) unless INTERACTIVE_DEBUG_MODE

        Dir.chdir(@cwd)
    end

    def validate_nodes(nodes, container_node = nil)

        container_port_map = { }

        unless container_node.nil? || container_node['container_port_map'].nil?

            container_node['container_port_map'].each_value { |v| container_port_map.merge!(v) }

            ssh = ssh_create(container_node['ipaddress'], 'vagrant', Dir.home + '/.vagrant/insecure_key')
            container_port_map.each_key do |id|

                Timeout::timeout(300) do
                    while true do
                        result = ssh_exec!(ssh, "sudo docker logs #{id} | tail")
                        break if result[:out].rindex('Chef Run complete')
                        puts "Waiting for container #{id}..."
                        sleep(2)
                    end
                end
            end
        end

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
        puts("** Knife Status:\n#{status}")
        # expect(status.strip.length).to eq(0)

        nodes.each do |n|

            knife_cmd = Chef::Knife::NodeShow.new
            knife_cmd.name_args = [ n ]
            knife_cmd.config[:attribute] = 'environment'
            environment = run_knife(knife_cmd)

            expect(environment[/environment: (\w+)/, 1]).to eq('DEV')
        end

        wordpress_ips = [ ]

        nodes.each do |n|

            node = Chef::Node.load(n)
            container_port = container_port_map[node['fqdn']]

            if container_node.nil?

                next if n.start_with?('database')

                ip = node['ipaddress']

                resp = http_fetch("http://#{ip}")
                expect(resp.code).to eq('200')

                wordpress_ips << ip if n.start_with?('wordpress')

            elsif !container_port.nil?

                timeout(30) do
                    resp = http_fetch("http://#{container_node['ipaddress']}:#{container_port}")
                    expect(resp.code).to eq('200')
                end
            end
        end

        if container_node.nil?

            knife_cmd = Chef::Knife::Ssh.new
            knife_cmd.name_args = [ 'name:loadbalancer-DEV-0',
                "cat /etc/haproxy/haproxy.cfg | awk '/server wordpress-DEV/ {print substr($3,0,length($3)-2)}'" ]

            knife_cmd.config[:attribute] = 'ipaddress'
            knife_cmd.config[:ssh_user] = 'vagrant'
            knife_cmd.config[:identity_file] = Dir.home + '/.vagrant/insecure_key'
            ips = run_knife(knife_cmd).lines.map.collect { |line| line[/\d+\.\d+\.\d+\.\d+ (\d+\.\d+\.\d+\.\d+)/, 1] }

            expect(wordpress_ips.sort).to eq(ips.sort)
        end
    end

    it "should test stack build, scale and destroy" do

        knife_cmd = Chef::Knife::StackInitializeRepo.new
        knife_cmd.config[:repo_path] = @repo_path
        knife_cmd.config[:certs] = 'wpweb.stackbuilder.org,wpdb.stackbuilder.org'
        knife_cmd.config[:stack_environments] = 'DEV,TEST,PROD'
        knife_cmd.config[:cookbooks] =
                'haproxy:=1.6.6,' +
                'mysql:=5.6.1,' +
                'mysql-chef_gem:=0.0.5,' +
                'apache2:=2.0.0,' +
                'wordpress:=2.3.0'

        knife_cmd.run

        # Copy the test data into the repo
        system("cp -fr #{@test_data_path}/test_repo/* #{@repo_path}")

        knife_cmd = Chef::Knife::StackUploadRepo.new
        knife_cmd.config[:repo_path] = @repo_path
        run_knife(knife_cmd)

        if RUN_TESTS.include?(:wordpress)

            puts "Building DEV stack"

            knife_cmd = Chef::Knife::StackBuild.new
            knife_cmd.name_args = [ @test_data_path + '/test_repo/stack1.yml' ]
            knife_cmd.config[:stack_id] = @stack_ids[:dev]
            knife_cmd.config[:environment] = 'DEV'
            knife_cmd.config[:repo_path] = @repo_path
            knife_cmd.run

            validate_nodes(['database-DEV-0', 'wordpress-DEV-0', 'loadbalancer-DEV-0'])

            puts "Scaling up the DEV stack web tier"

            knife_cmd = Chef::Knife::StackBuild.new
            knife_cmd.name_args = [ @test_data_path + '/test_repo/stack1.yml' ]
            knife_cmd.config[:stack_id] = @stack_ids[:dev]
            knife_cmd.config[:environment] = 'DEV'
            knife_cmd.config[:node] = 'wordpress:2'
            knife_cmd.config[:repo_path] = @repo_path
            knife_cmd.run

            validate_nodes(['database-DEV-0', 'wordpress-DEV-0', 'wordpress-DEV-1', 'loadbalancer-DEV-0'])

            puts "Scaling down the DEV stack web tier"

            knife_cmd = Chef::Knife::StackBuild.new
            knife_cmd.name_args = [ @test_data_path + '/test_repo/stack1.yml' ]
            knife_cmd.config[:stack_id] = @stack_ids[:dev]
            knife_cmd.config[:environment] = 'DEV'
            knife_cmd.config[:node] = 'wordpress:1'
            knife_cmd.config[:repo_path] = @repo_path
            knife_cmd.run

            validate_nodes(['database-DEV-0', 'wordpress-DEV-0', 'loadbalancer-DEV-0'])

            puts "Destroying the DEV stack"

            stack = StackBuilder::Stack::Stack.new(
                StackBuilder::Chef::NodeProvider.new(@repo_path, 'DEV'),
                @test_data_path + '/test_repo/stack1.yml',
                @stack_ids[:dev] )

            stack.destroy

            knife_cmd = Chef::Knife::NodeList.new
            node_list = run_knife(knife_cmd).split
            expect(node_list.empty?).to be_truthy
        end

        if RUN_TESTS.include?(:generic)

            puts "Building the TEST stack"

            knife_cmd = Chef::Knife::StackBuild.new
            knife_cmd.name_args = [ @test_data_path + '/test_repo/stack2.yml' ]
            knife_cmd.config[:stack_id] = @stack_ids[:test]
            knife_cmd.config[:environment] = 'TEST'
            knife_cmd.config[:repo_path] = @repo_path
            knife_cmd.run

            knife_cmd = Chef::Knife::NodeList.new
            node_list = run_knife(knife_cmd).split
            expect(node_list).to include('test-TEST-0')

            knife_cmd = Chef::Knife::Ssh.new
            knife_cmd.name_args = [ 'name:test-TEST-0', "sudo su -c '[ -e ~/stack_configured ] && echo yes'" ]
            knife_cmd.config[:attribute] = 'ipaddress'
            knife_cmd.config[:ssh_user] = 'vagrant'
            knife_cmd.config[:identity_file] = Dir.home + '/.vagrant/insecure_key'
            result = run_knife(knife_cmd).chomp
            expect(result[/\d+\.\d+\.\d+\.\d+ (\w+)/, 1]).to eq('yes')

            knife_cmd = Chef::Knife::Ssh.new
            knife_cmd.name_args = [ 'name:test-TEST-0', "sudo su -c 'cat /etc/chef/encrypted_data_bag_secret'" ]
            knife_cmd.config[:attribute] = 'ipaddress'
            knife_cmd.config[:ssh_user] = 'vagrant'
            knife_cmd.config[:identity_file] = Dir.home + '/.vagrant/insecure_key'
            result = run_knife(knife_cmd).chomp

            expect(result[/\d+\.\d+\.\d+\.\d+ (.*)/, 1]).to eq(IO.read("#{@repo_path}/secrets/TEST"))

            puts "Destroying the TEST stack"

            stack = StackBuilder::Stack::Stack.new(
                StackBuilder::Chef::NodeProvider.new(@repo_path, 'TEST'),
                @test_data_path + '/test_repo/stack2.yml',
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

        if RUN_TESTS.include?(:containter)

            puts "Creating a container stack"

            knife_cmd = Chef::Knife::StackBuild.new
            knife_cmd.name_args = [ @test_data_path + '/test_repo/stack3.yml' ]
            knife_cmd.config[:stack_id] = @stack_ids[:dev]
            knife_cmd.config[:environment] = 'DEV'
            knife_cmd.config[:repo_path] = @repo_path
            knife_cmd.run

            node = Chef::Node.load('database-DEV-0')
            container_port_map = node['container_port_map']

            expect(container_port_map['wordpress'].nil?).to be_falsey
            expect(container_port_map['wordpress'].size).to eq(1)

            validate_nodes(['database-DEV-0', 'wordpress_web-DEV-0'], node)

            puts "Scaling a container stack"

            knife_cmd = Chef::Knife::StackBuild.new
            knife_cmd.name_args = [ @test_data_path + '/test_repo/stack3.yml' ]
            knife_cmd.config[:stack_id] = @stack_ids[:dev]
            knife_cmd.config[:node] = 'wordpress_web:3'
            knife_cmd.config[:environment] = 'DEV'
            knife_cmd.config[:repo_path] = @repo_path
            knife_cmd.run

            node = Chef::Node.load('database-DEV-0')
            container_port_map = node['container_port_map']
            expect(container_port_map['wordpress'].size).to eq(3)

            validate_nodes([ 'database-DEV-0', 'wordpress_web-DEV-0',
                'wordpress_web-DEV-1', 'wordpress_web-DEV-2' ], node)

            knife_cmd = Chef::Knife::StackBuild.new
            knife_cmd.name_args = [ @test_data_path + '/test_repo/stack3.yml' ]
            knife_cmd.config[:stack_id] = @stack_ids[:dev]
            knife_cmd.config[:node] = 'wordpress_web:1'
            knife_cmd.config[:environment] = 'DEV'
            knife_cmd.config[:repo_path] = @repo_path
            knife_cmd.run

            node = Chef::Node.load('database-DEV-0')
            container_port_map = node['container_port_map']
            expect(container_port_map['wordpress'].size).to eq(1)

            validate_nodes(['database-DEV-0', 'wordpress_web-DEV-0', ], node)

            puts "Destroying a container stack"

            stack = StackBuilder::Stack::Stack.new(
                StackBuilder::Chef::NodeProvider.new(@repo_path, 'DEV'),
                @test_data_path + '/test_repo/stack3.yml',
                @stack_ids[:dev] )

            stack.destroy
        end
    end
end