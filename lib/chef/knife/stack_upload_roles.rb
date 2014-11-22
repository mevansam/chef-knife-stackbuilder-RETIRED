# Copyright (c) 2014 Mevan Samaratunga

require 'chef/knife/stackbuilder_base'

class Chef
    class Knife

        class StackUploadRoles < Knife

            include Knife::StackBuilderBase

            banner "knife stack upload roles (options)"

            option :repo_path,
                :long => "--repo_path REPO_PATH",
                :description => "The path to the Chef repo containing " +
                    "the roles within a 'roles' folder.",
                :default => './'

            option :role,
                :long => "--role NAME",
                :description => "The role upload/update"

            def run
                StackBuilder::Common::Config.logger.level = Chef::Log.logger.level

                repo = StackBuilder::Chef::Repo.new(config[:repo_path])
                repo.upload_roles(config[:role])
            end
        end

    end
end
