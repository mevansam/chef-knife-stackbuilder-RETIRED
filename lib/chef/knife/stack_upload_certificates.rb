# Copyright (c) 2014 Mevan Samaratunga

require 'chef/knife/stackbuilder_base'

class Chef
    class Knife

        class StackUploadCertificates < Knife

            include Knife::StackBuilderBase

            banner "knife stack upload certificates REPO_PATH (options)"

            option :env,
                   :long => "--env ENVIRONMENT",
                   :description => "Environment to upload/update"

            option :server,
                   :long => "--server NAME",
                   :description => "The name of the server whose " +
                        "certificate is to be uploaded"

            def run
                repo = StackBuilder::Chef::Repo.new(get_repo_path(name_args))
                repo.upload_certificates(config[:env], config[:server])
            end
        end

    end
end
