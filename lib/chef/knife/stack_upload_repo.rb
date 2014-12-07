# Copyright (c) 2014 Mevan Samaratunga

require 'chef/knife/stackbuilder_base'

class Chef
    class Knife

        class StackUploadRepo < Knife

            include Knife::StackBuilderBase

            banner "knife stack upload repo (options)"

            option :repo_path,
                :long => "--repo_path REPO_PATH",
                :description => "The path to the Chef repo.",
                :default => '.'

            def run
                StackBuilder::Common::Config.logger.level = Chef::Log.logger.level

                environment = getConfig(:environment)

                repo = StackBuilder::Chef::Repo.new(getConfig(:repo_path))

                berks_knife_config = getConfig(:berks_knife_config)
                ENV['BERKSHELF_CHEF_CONFIG'] = berks_knife_config unless berks_knife_config.nil?

                repo.upload_cookbooks
                repo.upload_roles

                repo.upload_environments(environment)
                repo.upload_data_bags(environment)
                repo.upload_certificates(environment)
            end
        end

    end
end
