# Copyright (c) 2014 Mevan Samaratunga

require 'chef/knife/stackbuilder_base'

class Chef
    class Knife

        class StackUploadDataBags < Knife

            include Knife::StackBuilderBase

            banner "knife stack upload data bags (options)"

            option :repo_path,
                :long => "--repo_path REPO_PATH",
                :description => "The path to the Chef repo containing the data_bags " +
                    "within a 'data_bags' folder. All data bags will be encrypted with " +
                    "keys per environment located in the 'secrets' folder of the repo.",
                :default => './'

            option :data_bag,
                :long => "--data_bag NAME",
                :description => "The data bag to upload/update"

            def run
                StackBuilder::Common::Config.logger.level = Chef::Log.logger.level

                environment = config[:environment]

                repo = StackBuilder::Chef::Repo.new(config[:repo_path])
                repo.upload_data_bags(environment, config[:data_bag])
            end
        end

    end
end
