# Copyright (c) 2014 Mevan Samaratunga

require 'chef/knife/stackbuilder_base'

class Chef
    class Knife

        class StackUploadRepo < Knife

            include Knife::StackBuilderBase

            banner "knife stack upload repo REPO_PATH (options)"

            def run
                repo = StackBuilder::Chef::Repo.new(get_repo_path(name_args))

                repo.upload_environments
                repo.upload_databags
                repo.upload_cookbooks
                repo.upload_roles
            end
        end

    end
end
