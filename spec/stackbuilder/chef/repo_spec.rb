# Copyright (c) 2014 Mevan Samaratunga

require File.expand_path('../../../spec_helper', __FILE__)

include StackBuilder::Common::Helpers

describe StackBuilder::Chef do

    before(:all) do

        @logger = StackBuilder::Common::Config.logger

        @tmp_dir = Dir.mktmpdir
        @repo_path = "#{@tmp_dir}/test_repo"

        @test_data_path = File.expand_path('../../../data', __FILE__)
        @knife_config = @test_data_path + '/chef-zero_knife.rb'

        @logger.debug("Test repo path is #{@tmp_dir}.")
    end

    after(:all) do
        FileUtils.rm_rf(@tmp_dir)
    end

    it "should create a test repository" do

        system("rm -fr #{@repo_path}")

        expect {

            # Repo does not exist so it cannot be loaded
            StackBuilder::Chef::Repo.new(@repo_path)

        }.to raise_error(StackBuilder::Chef::RepoNotFoundError)

        repo = StackBuilder::Chef::Repo.new(
            @repo_path,
            nil,
            'DEV,TEST,PROD',
            'mysql:=5.6.1, wordpress:~> 2.3.0' )

        # Copy the test data into the repo
        system("cp -fr #{@test_data_path}/test_repo/* #{@repo_path}")

        expect(repo.environments).to match_array([ 'DEV', 'TEST', 'PROD' ])

        expect(Dir["#{@repo_path}/etc/**/*.yml"].map { |f| f[/\/(\w+).yml$/, 1] } )
            .to match_array([ 'DEV', 'TEST', 'PROD' ])
        expect(Dir["#{@repo_path}/environments/**/*.rb"].map { |f| f[/\/(\w+).rb$/, 1] } )
            .to match_array([ 'DEV', 'TEST', 'PROD' ])
        expect(Dir["#{@repo_path}/stacks/**/*.yml"].map { |f| f[/\/(\w+).yml$/, 1] } )
            .to match_array([ 'Stack1', 'Stack2', 'Stack3' ])
    end

    it "should load an existing repositories environments" do

        expect {

            # Invalid repo location
            StackBuilder::Chef::Repo.new(@tmp_dir)

        }.to raise_error(StackBuilder::Chef::InvalidRepoError)

        # Repo does not exist so it cannot be loaded
        repo = StackBuilder::Chef::Repo.new(@repo_path)
        expect(repo.environments).to match_array([ 'DEV', 'TEST', 'PROD' ])
        expect(repo.stacks).to match_array([ 'Stack1', 'Stack2', 'Stack3' ])

        repo.upload_environments

        env_data = { }
        knife_cmd = Chef::Knife::EnvironmentShow.new

        [ 'DEV', 'TEST' ].each do |env_name|

            knife_cmd.name_args = [ env_name ]
            env_data[env_name] = YAML.load(run_knife(knife_cmd))
        end

        expect(env_data['DEV']['override_attributes']['attribA']['key1']).to eq('DEV_AAAA1111')
        expect(env_data['DEV']['override_attributes']['attribA']['key2']).to eq('DEV_AAAA2222')
        expect(env_data['DEV']['override_attributes']['attribB']['key1']).to eq('DEV_BBBB1111')
        expect(env_data['TEST']['override_attributes']['attribA']['key1']).to eq('TEST_AAAA1111')
        expect(env_data['TEST']['override_attributes']['attribA']['key2']).to eq('TEST_AAAA2222')
        expect(env_data['TEST']['override_attributes']['attribB']['key1']).to eq('TEST_BBBB1111')
    end

    it "should load an existing repositories databags" do

        repo = StackBuilder::Chef::Repo.new(@repo_path)
        repo.upload_databags
        repo.upload_databags # repeat to ensure update happens

        knife_cmd = Chef::Knife::DataBagList.new
        data_bag_list = run_knife(knife_cmd).split

        value_map = { }
        data_bag_list.each do |data_bag_name|

            env_name = data_bag_name[/-(\w+)$/, 1]

            knife_cmd = Chef::Knife::DataBagShow.new
            knife_cmd.name_args = [ data_bag_name ]
            data_bag_items = run_knife(knife_cmd).split

            data_bag_items.each do |data_bag_item|

                knife_cmd = Chef::Knife::DataBagShow.new
                knife_cmd.name_args = [ data_bag_name, data_bag_item ]
                knife_cmd.config[:secret] = repo.get_secret(env_name)
                data_bag_item_value = YAML.load(run_knife(knife_cmd))
                value = data_bag_item_value["value"]

                value_map["#{data_bag_name}:#{data_bag_item}"] = value
            end
        end

        expect(value_map["dbA-DEV:key1"]).to eq("DEV_AAAA1111")
        expect(value_map["dbA-DEV:key2"]).to eq("DEV_AAAA2222")
        expect(value_map["dbA-DEV:key3"]).to eq("DEV_AAAA3333")
        expect(value_map["dbB-DEV:key1"]).to eq("DEV_BBBB1111")
        expect(value_map["dbA-TEST:key1"]).to eq("TEST_AAAA1111")
        expect(value_map["dbA-TEST:key2"]).to eq("TEST_AAAA2222_override")
        expect(value_map["dbA-TEST:key4"]).to eq("TEST_AAAA4444")
        expect(value_map["dbB-TEST:key1"]).to eq("TEST_BBBB1111")
    end
end
