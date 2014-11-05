# Copyright (c) 2014 Mevan Samaratunga

require 'chef/knife/stackbuilder_base'

class Chef
    class Knife

        class StackUploadEnvironments < Knife

            include Knife::StackBuilderBase

            banner "knife stack upload environments REPO_PATH (options)"

            option :env,
               :long => "--env ENVIRONMENT",
               :description => "Environment to upload/update"

            def run
                repo = StackBuilder::Chef::Repo.new(get_repo_path(name_args))
                repo.upload_environments(config[:env])
            end
        end

    end
end
