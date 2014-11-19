# Copyright (c) 2014 Mevan Samaratunga

require File.expand_path('../../../spec_helper', __FILE__)

include StackBuilder::Common::Helpers

describe StackBuilder::Chef do

    before(:all) do

        @logger = StackBuilder::Common::Config.logger

        @tmp_dir = Dir.mktmpdir
        @logger.debug("Test repo path is #{@tmp_dir}.")

        @repo_path = "#{@tmp_dir}/test_repo"
        @test_data_path = File.expand_path('../../../data', __FILE__)
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
            "wpweb.stackbuilder.org,wpdb.stackbuilder.org",
            'DEV,TEST,PROD',
            'mysql:=5.6.1, wordpress:=2.3.0' )

        # Copy the test data into the repo
        system("cp -fr #{@test_data_path}/test_repo/* #{@repo_path}")

        expect(repo.environments).to match_array([ 'DEV', 'TEST', 'PROD' ])

        expect(Dir["#{@repo_path}/etc/**/*.yml"].map { |f| f[/\/(\w+).yml$/, 1] } )
            .to match_array([ 'DEV', 'TEST', 'PROD' ])
        expect(Dir["#{@repo_path}/environments/**/*.rb"].map { |f| f[/\/(\w+).rb$/, 1] } )
            .to match_array([ 'DEV', 'TEST', 'PROD' ])
        expect(Dir["#{@repo_path}/stacks/**/*.yml"].map { |f| f[/\/(\w+).yml$/, 1] } )
            .to match_array([ 'Stack1', 'Stack2', 'Stack3' ])

        expect(File.exist?("#{@repo_path}/.certs/cacert.pem")).to be true
        [ 'wpweb.stackbuilder.org', 'wpdb.stackbuilder.org' ].each do |server|
            expect(File.exist?("#{@repo_path}/.certs/#{server}/key.pem")).to be true
            expect(File.exist?("#{@repo_path}/.certs/#{server}/cert.pem")).to be true
        end
    end

    it "should load an existing repository's environments" do

        expect {

            # Invalid repo location
            StackBuilder::Chef::Repo.new(@tmp_dir)

        }.to raise_error(StackBuilder::Chef::InvalidRepoError)

        # Repo does not exist so it cannot be loaded
        repo = StackBuilder::Chef::Repo.new(@repo_path)
        expect(repo.environments).to match_array([ 'DEV', 'TEST', 'PROD' ])
        expect(repo.stacks).to match_array([ 'Stack1', 'Stack2', 'Stack3' ])

        knife_cmd = Chef::Knife::StackUploadEnvironments.new
        knife_cmd.name_args = [ @repo_path ]
        run_knife(knife_cmd)

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

    it "should load an existing repository's certificates as data-bags" do

        knife_cmd = Chef::Knife::StackUploadCertificates.new
        knife_cmd.name_args = [ @repo_path ]
        run_knife(knife_cmd)

        repo = StackBuilder::Chef::Repo.new(@repo_path)

        cacert = IO.read("#{@repo_path}/.certs/cacert.pem")

        [ 'DEV', 'TEST', 'PROD' ].each do |env_name|

            data_bag_name = 'certificates-' + env_name

            knife_cmd = Chef::Knife::DataBagShow.new
            knife_cmd.name_args = [ data_bag_name ]
            data_bag_items = run_knife(knife_cmd).split

            data_bag_items.each do |data_bag_item|

                server_certs = Chef::EncryptedDataBagItem.load(data_bag_name, data_bag_item, repo.get_secret(env_name))

                expect(server_certs['cacert']).to eq(cacert)
                expect(server_certs['cert']).to eq(IO.read("#{@repo_path}/.certs/#{data_bag_item}/cert.pem"))
                expect(server_certs['key']).to eq(IO.read("#{@repo_path}/.certs/#{data_bag_item}/key.pem"))
            end
        end
    end

    it "should load an existing repository's data-bags" do

        knife_cmd = Chef::Knife::StackUploadDataBags.new
        knife_cmd.name_args = [ @repo_path ]
        run_knife(knife_cmd)

        repo = StackBuilder::Chef::Repo.new(@repo_path)

        knife_cmd = Chef::Knife::DataBagList.new
        data_bag_list = run_knife(knife_cmd).split

        value_map = { }
        data_bag_list.each do |data_bag_name|

            unless data_bag_name.start_with?('certificates-')

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

    it "should upload cookbooks from the repo's Berksfile" do

        knife_cmd = Chef::Knife::StackUploadCookbooks.new
        knife_cmd.name_args = [ @repo_path ]
        knife_cmd.config[:berks_options] = '--force,--no-freeze'
        run_knife(knife_cmd)

        knife_cmd = Chef::Knife::CookbookList.new
        cookbook_list = run_knife(knife_cmd).split

        cookbooks = { }
        (0..cookbook_list.size).step(2) { |i| cookbooks[cookbook_list[i]] = cookbook_list[i+1] }

        expect(cookbooks['mysql']).to eq('5.6.1')
        expect(cookbooks['wordpress']).to eq('2.3.0')
    end

    it "should upload the repository's roles to chef" do

        ENV['ENV_KEY1'] = "env_value1"
        ENV['ENV_KEY2'] = "env_value2"

        knife_cmd = Chef::Knife::StackUploadRoles.new
        knife_cmd.name_args = [ @repo_path ]
        run_knife(knife_cmd)

        knife_cmd = Chef::Knife::RoleList.new
        role_list = run_knife(knife_cmd).split
        expect(role_list.include?('wordpress_db')).to be_truthy
        expect(role_list.include?('wordpress_web')).to be_truthy

        role_env_values = { }

        [ 'wordpress_db', 'wordpress_web' ].each do |role|

            knife_cmd = Chef::Knife::RoleShow.new
            knife_cmd.name_args = [ role ]
            role_attribs = YAML.load(run_knife(knife_cmd))
            role_env_values[role] = role_attribs['override_attributes']['env_value']
        end

        expect(role_env_values['wordpress_web']).to eq(ENV['ENV_KEY1'])
        expect(role_env_values['wordpress_db']).to eq(ENV['ENV_KEY2'])
    end

end
