# Copyright (c) 2014 Mevan Samaratunga

require 'chef/knife/stackbuilder_base'

class Chef
    class Knife

        class StackBuild < Knife

            include Knife::StackBuilderBase

            banner 'knife stack build STACK_FILE (options)'

            option :stack_id,
                :long => "--stack_id STACK_ID",
                :description => "The unique ID for the stack. If a stack with the given" +
                    "ID does not exist then a new one will be create. If a stack for the" +
                    "given ID exists then it will be initialized with its current state."

            option :node,
               :events => "--node NODE_TYPE_NAME[:SCALE]",
               :description => "Applies the events to all hosts of a given node type. The " +
                   "node type is the value of the node key of a list of stack nodes"

            option :overrides,
                :long => "--overrides OVERRIDES",
                :description => "JSON string or file ending with .json containing " +
                    "attributes to be overridden"

            option :events,
                :events => "--events EVENTS",
                :description => "List of comma separate events to apply. If no events are " +
                    "provided then events 'create', 'install', 'configure' will be applied " +
                    "to each new host that is either created or bootstrapped first time. If " +
                    "node already exists then only the 'configure' event is applied. When " +
                    "the 'configure' event is applied chef-client will be run on each node. " +
                    "If the 'update' event is applied then the nodes run list will be updated " +
                    "and chef-client will be run."

            option :repo_path,
               :long => "--repo_path REPO_PATH",
               :description => "The path to the Chef repo. This is required in order " +
                   "to copy the correct encryption keys from the 'secrets' folder to " +
                   "the target host as well as to read the externalized environment",
               :default => './'

            def run
                StackBuilder::Common::Config.logger.level = Chef::Log.logger.level

                environment = config[:environment] || '_default'

                stack_file = name_args.first
                unless File.exist?(stack_file)
                    puts "Stack file '#{stack_file}' does not exist."
                    exit 1
                end

                stack = StackBuilder::Stack::Stack.new(
                    StackBuilder::Chef::NodeProvider.new(config[:repo_path], environment),
                    stack_file,
                    config[:stack_id],
                    config[:overrides] )

                node = config[:node]
                unless node.nil?
                    node_name = node[/(.*):(\d+)?/, 1]
                    node_scale = node[/(.*):(\d+)?/, 2]
                    node_scale = node_scale.to_i unless node_scale.nil?
                end

                stack.orchestrate(config[:events], node_name, node_scale)
            end
        end

    end
end
