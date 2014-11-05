# Copyright (c) 2014 Mevan Samaratunga

require 'chef/knife/stackbuilder_base'

class Chef
    class Knife

        class StackUploadRoles < Knife

            include Knife::StackBuilderBase

            banner "knife stack upload roles REPO_PATH (options)"

            option :role,
               :long => "--role NAME",
               :description => "The role upload/update"

            def run
                repo = StackBuilder::Chef::Repo.new(get_repo_path(name_args))
                repo.upload_roles(config[:role])
            end
        end

    end
end
