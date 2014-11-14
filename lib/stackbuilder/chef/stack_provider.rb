# Copyright (c) 2014 Mevan Samaratunga

include StackBuilder::Common::Helpers

module StackBuilder::Chef

    class NodeProvider < StackBuilder::Stack::NodeProvider

        def initialize
        end

        def set_stack(stack, id, new = true)

            @stack = stack
            @id = id
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