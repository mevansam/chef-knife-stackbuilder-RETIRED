# Copyright (c) 2014 Mevan Samaratunga

require 'chef/knife/stackbuilder_base'

class Chef
    class Knife

        class StackUploadCookbooks < Knife

            include Knife::StackBuilderBase

            banner 'knife stack upload cookbooks (options)'

            option :repo_path,
                :long => "--repo_path REPO_PATH",
                :description => "The path to the Chef repo containing the Berkshelf file.",
                :default => '.'

            option :cookbook,
                :long => "--cookbook NAME",
                :description => "The cookbook upload/update"

            option :berks_options,
                :long => "--berks-options options",
                :description => "Comma separated list of berkshelf upload options"

            option :berks_knife_config,
               :long => "--berks-knife-config options",
               :description => "Knife configuration file to be passed to Berkshelf"

            def run
                StackBuilder::Common::Config.logger.level = Chef::Log.logger.level

                repo = StackBuilder::Chef::Repo.new(getConfig(:repo_path))

                berks_knife_config = getConfig(:berks_knife_config)
                ENV['BERKSHELF_CHEF_CONFIG'] = berks_knife_config unless berks_knife_config.nil?

                berks_options = getConfig(:berks_options)
                unless berks_options.nil?
                    repo.upload_cookbooks(getConfig(:cookbook), berks_options.gsub(/,/, ' '))
                else
                    repo.upload_cookbooks(getConfig(:cookbook))
                end
            end
        end

    end
end
