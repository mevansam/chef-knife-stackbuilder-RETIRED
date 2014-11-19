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

            case node_config['knife']['plugin']

                when 'vagrant'
                    return StackBuilder::Chef::VagrantNodeManager.new(@id, node_config)
                when 'esx'
                    raise NotImplemented, 'NodeProvider.get_node_manager'
                when 'xen'
                    raise NotImplemented, 'NodeProvider.get_node_manager'
                when 'baremetalcloud'
                    raise NotImplemented, 'NodeProvider.get_node_manager'
                when 'softlayer'
                    raise NotImplemented, 'NodeProvider.get_node_manager'
                when 'custom'
                    raise NotImplemented, 'NodeProvider.get_node_manager'
                else
                    return StackBuilder::Chef::HostNodeManager.new(@id, node_config)
            end
        end
    end
end