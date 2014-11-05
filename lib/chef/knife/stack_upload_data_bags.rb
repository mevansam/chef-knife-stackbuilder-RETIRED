# Copyright (c) 2014 Mevan Samaratunga

require 'chef/knife/stackbuilder_base'

class Chef
    class Knife

        class StackUploadDataBags < Knife

            include Knife::StackBuilderBase

            banner "knife stack upload data bags REPO_PATH (options)"

            option :env,
               :long => "--env ENVIRONMENT",
               :description => "Environment to upload/update"

            option :data_bag,
               :long => "--data_bag NAME",
               :description => "The data bag to upload/update"

            def run
                repo = StackBuilder::Chef::Repo.new(get_repo_path(name_args))
                repo.upload_databags(config[:env], config[:data_bag])
            end
        end

    end
end
