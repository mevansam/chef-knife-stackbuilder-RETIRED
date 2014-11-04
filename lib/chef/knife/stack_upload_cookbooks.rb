# Copyright (c) 2014 Mevan Samaratunga

require 'chef/knife/stackbuilder_base'

class Chef
    class Knife

        class StackUploadCookbook < Knife

            include Knife::StackBuilderBase

            banner 'knife stack upload cookbook REPO_PATH (options)'

            option :cookbook,
               :long => "--cookbook NAME",
               :description => "The cookbook upload/update"

            def run
            end
        end

        class StackUploadCookbooks < Knife

            include Knife::StackBuilderBase

            banner 'knife stack upload cookbooks REPO_PATH (options)'

            def run
            end
        end

    end
end
