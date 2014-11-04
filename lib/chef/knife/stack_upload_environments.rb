# Copyright (c) 2014 Mevan Samaratunga

require 'chef/knife/stackbuilder_base'

class Chef
    class Knife

        class StackUploadEnvironment < Knife

            include Knife::StackBuilderBase

            banner "knife stack upload environment REPO_PATH (options)"

            option :envs,
               :long => "--env ENVIRONMENT",
               :description => "Environment to upload/update"

            def run
            end
        end

        class StackUploadEnvironments < Knife

            include Knife::StackBuilderBase

            banner "knife stack upload environments REPO_PATH (options)"

            def run
            end
        end

    end
end
