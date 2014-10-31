# Copyright (c) 2014 Mevan Samaratunga

module StackBuilder::Chef

    class RepoNotFoundError < StackBuilder::Common::StackBuilderError; end

    class Repo

        include ERB::Util

        REPO_DIRS = [
                "cookbooks",
                "environments",
                "secrets",
                "databags",
                "roles",
                "stacks"
            ]

        def initialize(path, environments = nil, certificates = nil, cookbooks = nil)

            @logger = StackBuilder::Common::Config.logger

            if !Dir.exist?(path)

                raise RepoNotFoundError,
                      "Unable to load repo @ #{path}. If you need to create a repo please " +
                      "provide the list of environments at a minimum" if environments.nil?

                REPO_DIRS.each do |folder|
                    system("mkdir -p #{path}/#{folder}")
                end

                # Create Berksfile
                @berks_cookbooks = cookbooks.nil? ? [] : cookbooks.split(',').map { |s| s.strip.split(':') }
                berksfile_template = IO.read(File.expand_path('../Berksfile.erb', __FILE__))

                berksfile = ERB.new(berksfile_template, nil, '-<>').result(binding)
                File.open("#{path}/Berksfile", 'w+') { |f| f.write(berksfile) }

                # Create Environments
                environments = environments.split(',').map { |s| s.strip }
                environment_template = IO.read(File.expand_path('../Environment.erb', __FILE__))

                environments.each do |env_name|
                    @environment = env_name
                    envfile = ERB.new(environment_template, nil, '-<>').result(binding)
                    File.open("#{path}/environments/#{env_name}.rb", 'w+') { |f| f.write(envfile) }
                end

                # Create Environment secrets
                environments.each do |env_name|
                    key = SecureRandom.uuid()
                    File.open("#{path}/secrets/#{env_name}", 'w+') { |f| f.write(key) }
                end
            end
        end
    end
end
