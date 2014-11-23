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
                :long => "--berks_options options",
                :description => "Comma separated list of berkshelf upload options"

            def run
                StackBuilder::Common::Config.logger.level = Chef::Log.logger.level

                repo = StackBuilder::Chef::Repo.new(config[:repo_path])

                berks_options = config[:berks_options]
                unless berks_options.nil?
                    repo.upload_cookbooks(config[:cookbook], berks_options.gsub(/,/, ' '))
                else
                    repo.upload_cookbooks(config[:cookbook])
                end
            end
        end

    end
end
