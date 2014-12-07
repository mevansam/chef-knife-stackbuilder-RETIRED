# Copyright (c) 2014 Mevan Samaratunga

require 'chef/knife/stackbuilder_base'

class Chef
    class Knife

        class StackDelete < Knife

            include Knife::StackBuilderBase

            banner 'knife stack delete STACK_FILE (options)'

            option :stack_id,
               :long => "--stack-id STACK_ID",
               :description => "The ID of the stack to delete.",
               :required => true

            option :repo_path,
               :long => "--repo_path REPO_PATH",
               :description => "The path to the Chef repo. This is required " +
                   "in order read the externalized environment",
               :default => '.'

            def run
                StackBuilder::Common::Config.logger.level = Chef::Log.logger.level

                environment = getConfig(:environment) || '_default'
                stack_file = name_args.first

                if stack_file=~/[-_+=.0-9a-zA-Z]+/
                    stack_file = Dir.getwd + '/' + stack_file + (stack_file.end_with?('.yml') ? '' : '.yml')
                end

                unless File.exist?(stack_file)
                    puts "Stack file '#{stack_file}' does not exist."
                    exit 1
                end

                stack = StackBuilder::Stack::Stack.new(
                    StackBuilder::Chef::NodeProvider.new(getConfig(:repo_path), environment),
                    stack_file,
                    getConfig(:stack_id) )

                stack.destroy
            end
        end

    end
end
