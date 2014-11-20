# Copyright (c) 2014 Mevan Samaratunga

include StackBuilder::Common::Helpers

module StackBuilder::Chef

    class NodeProvider < StackBuilder::Stack::NodeProvider

        def initialize
        end

        def set_stack(stack, id)

            @stack = stack
            @id = id

            Chef::Config[:chef_server_url] = stack['chef_server_url'] if stack.has_key?('chef_server_url')
            Chef::Config[:environment] = stack['environment'] if stack.has_key?('environment')
        end

        def get_node_manager(node_config)

            knife_config = node_config['knife']
            if knife_config.has_key?('plugin')

                case knife_config['plugin']
                    when 'vagrant'
                        return StackBuilder::Chef::VagrantNodeManager.new(@id, node_config)

                    # TODO: Refactor so that managers are pluggable from other gems

                    else
                        raise ArgumentError, "Unknown plugin #{knife['plugin']}."
                end

            elsif knife_config.has_key?('create')
                return StackBuilder::Chef::GenericNodeManager.new(@id, node_config)

            else
                return StackBuilder::Chef::NodeManager.new(@id, node_config)
            end
        end
    end
end