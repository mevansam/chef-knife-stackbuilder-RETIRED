# Copyright (c) 2014 Mevan Samaratunga

require 'chef/knife/stackbuilder_base'

class Chef
    class Knife

        class StackUploadDataBag < Knife

            include Knife::StackBuilderBase

            banner "knife stack upload data bag REPO_PATH (options)"

            option :envs,
               :long => "--env ENVIRONMENT",
               :description => "Environment to upload/update"

            option :data_bag,
               :long => "--data_bag NAME",
               :description => "The data bag to upload/update"

            def run
            end
        end

        class StackUploadDataBags < Knife

            include Knife::StackBuilderBase

            deps do
            end

            banner "knife stack upload data bags REPO_PATH (options)"

            def run
            end
        end

    end
end
