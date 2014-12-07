# Copyright (c) 2014 Mevan Samaratunga

require 'chef/knife/stackbuilder_base'

class Chef
    class Knife

        class StackUploadCertificates < Knife

            include Knife::StackBuilderBase

            banner "knife stack upload certificates"

            option :repo_path,
                :long => "--repo_path REPO_PATH",
                :description => "The path to the Chef Berkshelf repo. All the " +
                    "certificates associated with this repository would have " +
                    "been copied to a hidden folder '.certs' within this path " +
                    "when it was initialized.",
                :default => '.'

            option :server,
                :long => "--server NAME",
                :description => "The name of the server whose " +
                    "certificate is to be uploaded"

            def run
                StackBuilder::Common::Config.logger.level = Chef::Log.logger.level

                environment = getConfig(:environment)

                repo = StackBuilder::Chef::Repo.new(getConfig(:repo_path))
                repo.upload_certificates(environment, getConfig(:server))
            end
        end

    end
end
