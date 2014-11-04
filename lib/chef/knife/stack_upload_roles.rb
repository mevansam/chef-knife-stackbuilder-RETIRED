# Copyright (c) 2014 Mevan Samaratunga

require 'chef/knife/stackbuilder_base'

class Chef
    class Knife

        class StackUploadRole < Knife

            include Knife::StackBuilderBase

            banner "knife stack upload role REPO_PATH (options)"

            option :cookbook,
               :long => "--role NAME",
               :description => "The role upload/update"

            def run
            end
        end

        class StackUploadRoles < Knife

            include Knife::StackBuilderBase

            banner "knife stack upload roles REPO_PATH (options)"

            def run
            end
        end

    end
end
