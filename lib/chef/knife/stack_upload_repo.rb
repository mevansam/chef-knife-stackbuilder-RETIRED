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
                :default => './'

            def run
                StackBuilder::Common::Config.logger.level = Chef::Log.logger.level

                repo = StackBuilder::Chef::Repo.new(config[:repo_path])

                repo.upload_environments
                repo.upload_data_bags
                repo.upload_cookbooks
                repo.upload_roles
                repo.upload_certificates
            end
        end

    end
end
