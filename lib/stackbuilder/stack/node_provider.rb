# Copyright (c) 2014 Mevan Samaratunga

include StackBuilder::Common::Helpers

module StackBuilder::Stack

    class NodeProvider

        # Returns all the nodes matching the given
        # id as a hash of node => [ instances ]
        def set_stack_id(id, new = true)
            raise NotImplemented, 'NodeProvider.get_node_instances'
        end

        def get_node_task(node_config)
            raise NotImplemented, 'NodeProvider.get_node'
        end
    end
end