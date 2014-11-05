# Copyright (c) 2014 Mevan Samaratunga

require 'chef/knife/stackbuilder_base'

class Chef
    class Knife

        class StackInitializeRepo < Knife

            include Knife::StackBuilderBase

            banner 'knife stack initialize repo REPO_PATH (options)'

            option :cert_path,
                :long => "--cert_path CERT_PATH",
                :description => "Path containing folders with server certificates. Each folder " +
                    "within this path should be named after the server for which the certs are " +
                    "meant post-fixed by _{ENV_NAME}. If name is not post-fixed then the cert " +
                    "will be uploaded to all environments"

            option :certs,
                :long => "--certs SERVER_NAMES",
                :description => "Comma separated list of server names for which self-signed " +
                    "certificates will be generated."

            option :envs,
               :long => "--stack_envs ENVIRONMENTS",
               :description => "Comma separated list of environments to generate"

            option :cookbooks,
               :long => "--cookbooks COOKBOOKS",
               :description => "A comma separated list of cookbooks and their versions to be " +
                    "added to the Berksfile i.e. \"mysql:=5.6.1, wordpress:~> 2.3.0\""

            def run
                repo_path = get_repo_path(name_args)
                cert_path = config[:cert_path]
                certs = config[:certs]

                if !cert_path.nil? && !certs.nil?
                    puts "Only one of --cert_path or --certs can be specified."
                    show_usage
                    exit 1
                end

                StackBuilder::Chef::Repo.new(
                    repo_path,
                    cert_path.nil? ? certs : cert_path,
                    config[:stack_envs],
                    config[:cookbooks] )
            end
        end

    end
end
