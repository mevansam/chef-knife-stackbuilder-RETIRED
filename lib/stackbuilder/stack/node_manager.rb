# Copyright (c) 2014 Mevan Samaratunga

include StackBuilder::Common::Helpers

module StackBuilder::Stack

    class NodeManager

        def get_scale
            @scale
        end

        def set_scale(scale)
            @scale = scale
        end

        def node_attributes
            raise NotImplemented, 'NodeManager.node_attributes'
        end

        def create(index)
            raise NotImplemented, 'NodeManager.create'
        end

        def process(index, events)
            raise NotImplemented, 'NodeManager.process'
        end

        def delete(index)
            raise NotImplemented, 'NodeManager.delete'
        end

    end
end