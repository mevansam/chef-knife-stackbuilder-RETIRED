# Copyright (c) 2014 Mevan Samaratunga

require 'chef/knife/stackbuilder_base'

class Chef
    class Knife

        class StackUploadEnvironments < Knife

            include Knife::StackBuilderBase

            banner "knife stack upload environments (options)"

            option :repo_path,
                :long => "--repo_path REPO_PATH",
                :description => "The path to the Chef repo containing " +
                    "the environments within an 'environments' folder.",
                :default => '.'

            def run
                StackBuilder::Common::Config.logger.level = Chef::Log.logger.level

                environment = getConfig(:environment)

                repo = StackBuilder::Chef::Repo.new(getConfig(:repo_path))
                repo.upload_environments(environment)
            end
        end

    end
end
