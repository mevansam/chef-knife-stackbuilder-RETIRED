# Copyright (c) 2014 Mevan Samaratunga

require 'chef/knife/stackbuilder_base'

class Chef
    class Knife

        class StackUploadCookbooks < Knife

            include Knife::StackBuilderBase

            banner 'knife stack upload cookbooks REPO_PATH (options)'

            option :cookbook,
               :long => "--cookbook NAME",
               :description => "The cookbook upload/update"

            def run
                repo = StackBuilder::Chef::Repo.new(get_repo_path(name_args))
                repo.upload_cookbooks(config[:cookbook])
            end
        end

    end
end
