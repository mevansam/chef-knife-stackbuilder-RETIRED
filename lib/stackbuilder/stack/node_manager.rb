# Copyright (c) 2014 Mevan Samaratunga

include StackBuilder::Common::Helpers

module StackBuilder::Stack

    class NodeManager

        def get_name
            raise StackBuilder::Common::NotImplemented, 'NodeManager.get_name'
        end

        def get_scale
            @scale.nil? ? 0 : @scale
        end

        def set_scale(scale)
            @scale = scale
        end

        def node_attributes
            raise StackBuilder::Common::NotImplemented, 'NodeManager.node_attributes'
        end

        def create(index)
            raise StackBuilder::Common::NotImplemented, 'NodeManager.create'
        end

        def process(index, events, attributes, target = nil)
            raise StackBuilder::Common::NotImplemented, 'NodeManager.process'
        end

        def delete(index)
            raise StackBuilder::Common::NotImplemented, 'NodeManager.delete'
        end

    end
end