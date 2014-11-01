# Copyright (c) 2014 Mevan Samaratunga

include StackBuilder::Common::Helpers

module StackBuilder::Chef

    class RepoNotFoundError < StackBuilder::Common::StackBuilderError; end
    class InvalidRepoError < StackBuilder::Common::StackBuilderError; end

    class Repo

        include ERB::Util

        attr_reader :environments

        REPO_DIRS = [
                'etc',
                'cookbooks',
                'environments',
                'secrets',
                'databags',
                'roles',
                'stacks'
            ]

        def initialize(path, certificates = nil, environments = nil, cookbooks = nil)

            @logger = StackBuilder::Common::Config.logger
            @repo_path = path

            if Dir.exist?(path)

                REPO_DIRS.each do |folder|
                    repo_folder = "#{path}/#{folder}"
                    raise InvalidRepoError,
                          "Repo folder #{repo_folder} is missing" unless Dir.exist?(repo_folder)
                end

                @environments = [ ]
                Dir["#{path}/environments/**/*.rb"].each do |envfile|
                    @environments << envfile[/\/(\w+).rb$/, 1]
                end

                @logger.debug("Found stack environments #{@environments}")
            else
                raise RepoNotFoundError,
                      "Unable to load repo @ #{path}. If you need to create a repo please " +
                      "provide the list of environments at a minimum" if environments.nil?

                REPO_DIRS.each do |folder|
                    system("mkdir -p #{path}/#{folder}")
                end

                # Create Berksfile
                @berks_cookbooks = cookbooks.nil? ? [] : cookbooks.split(',').map { |s| s.strip.split(':') }
                berksfile_template = IO.read(File.expand_path('../../tmpl/Berksfile.erb', __FILE__))

                berksfile = ERB.new(berksfile_template, nil, '-<>').result(binding)
                File.open("#{path}/Berksfile", 'w+') { |f| f.write(berksfile) }

                # Create Environments and Stacks
                @environments = environments.split(',').map { |s| s.strip }
                configfile_template = IO.read(File.expand_path('../../tmpl/Config.yml.erb', __FILE__))
                envfile_template = IO.read(File.expand_path('../../tmpl/Environment.rb.erb', __FILE__))
                stackfile_template = IO.read(File.expand_path('../../tmpl/Stack.yml.erb', __FILE__))

                i = 1
                @environments.each do |env_name|

                    @environment = env_name

                    configfile = ERB.new(configfile_template, nil, '-<>').result(binding)
                    File.open("#{path}/etc/#{env_name}.yml", 'w+') { |f| f.write(configfile) }

                    envfile = ERB.new(envfile_template, nil, '-<>').result(binding)
                    File.open("#{path}/environments/#{env_name}.rb", 'w+') { |f| f.write(envfile) }

                    stackfile = ERB.new(stackfile_template, nil, '-<>').result(binding)
                    File.open("#{path}/stacks/Stack#{i}.yml", 'w+') { |f| f.write(stackfile) }
                    i += 1
                end
                @environment = nil
            end

            # Load the stacks
            @stackfiles = { }
            Dir["#{path}/stacks/**/*.yml"].each do |stackfile|
                @stackfiles[stackfile[/\/(\w+).yml$/, 1]] = stackfile
            end
        end

        def stacks
            @stackfiles.keys
        end

        def upload_environments(environment = nil)

            environments = (environment.nil? ? @environments : [ environment ])
            knife_cmd = Chef::Knife::EnvironmentFromFile.new

            environments.each do |env_name|
                knife_cmd.name_args = [ "#{@repo_path}/environments/#{env_name}.rb" ]
                run_knife(knife_cmd)
            end
        end

        def upload_databags(environment = nil)

            environments = (environment.nil? ? @environments : [ environment ])

            knife_cmd = Chef::Knife::DataBagList.new
            data_bag_list = run_knife(knife_cmd).split

            Dir["#{@repo_path}/databags/*"].each do |data_bag_dir|

                data_bag_name = data_bag_dir[/\/(\w+)$/, 1]
                environments.each do |env_name|

                    data_bag = data_bag_name + '-' + env_name
                    unless data_bag_list.include?(data_bag)
                        knife_cmd = Chef::Knife::DataBagCreate.new
                        knife_cmd.name_args = data_bag
                        run_knife(knife_cmd)
                    end

                    env_vars = YAML.load_file("#{@repo_path}/etc/#{env_name}.yml")
                    secret = get_secret(env_name)

                    upload_data_bag_items(secret, data_bag_dir, data_bag, env_vars)

                    env_item_dir = data_bag_dir + '/' + env_name
                    upload_data_bag_items(secret, env_item_dir, data_bag, env_vars) if Dir.exist?(env_item_dir)
                end
            end
        end

        def upload_cookbooks(environment = nil)

            berksfile_path = "#{@repo_path}/Berksfile"
            debug_flag = (@logger.debug? ? ' --debug' : '')

            # Need to invoke Berkshelf from the shell as directly invoking it causes
            # cookbook validation to throw an exception when 'Berksfile.upload' is
            # called.
            #
            # TBD: More research needs to be done as direct invocation is preferable

            cmd = ""
            cmd += "export BERKSHELF_CHEF_CONFIG=#{ENV['BERKSHELF_CHEF_CONFIG']}; " if ENV.has_key?('BERKSHELF_CHEF_CONFIG')
            cmd += "berks install#{debug_flag} --berksfile=#{berksfile_path}; "
            cmd += "berks upload#{debug_flag} --berksfile=#{berksfile_path} --no-freeze; "
            system(cmd)
        end

        def upload_roles(environment = nil)

        end

        def get_secret(env_name)

            secretfile = "#{@repo_path}/secrets/#{env_name}"
            if File.exists?(secretfile)
                key = IO.read(secretfile)
            else
                key = SecureRandom.uuid()
                File.open("#{@repo_path}/secrets/#{env_name}", 'w+') { |f| f.write(key) }
            end

            key
        end

        private

        def upload_data_bag_items(secret, path, data_bag_name, env_vars)

            tmpfile = nil

            Dir["#{path}/*.json"].each do |data_bag_file|

                data_bag_items = evalMapValues(JSON.load(File.new(data_bag_file, 'r')), env_vars)

                data_bag_item_name = data_bag_file[/\/(\w+).json$/, 1]
                tmpfile = "#{Dir.tmpdir}/#{data_bag_item_name}.json"
                File.open("#{tmpfile}", 'w+') { |f| f.write(data_bag_items.to_json) }

                knife_cmd = Chef::Knife::DataBagFromFile.new
                knife_cmd.name_args = [ data_bag_name, tmpfile ]
                knife_cmd.config[:secret] = secret
                run_knife(knife_cmd)

                File.delete(tmpfile)
            end

        rescue Exception => msg
            File.delete(tmpfile) unless tmpfile.nil?
            @logger.error(msg)
        end
    end
end
