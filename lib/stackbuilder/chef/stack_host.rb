# Copyright (c) 2014 Mevan Samaratunga

include StackBuilder::Common::Helpers

module StackBuilder::Chef

    class HostNodeManager < StackBuilder::Stack::NodeManager

        attr_accessor :name

        def initialize(id, node_config)

            @id = id
            @name = node_config['node']
            @node_id = @name + '-' + @id

            @run_list = node_config['run_list'].join(',')
            @knife_options = node_config['knife']
        end

        def get_name
            @name
        end

        def get_scale
            get_stack_node_resources
        end

        def node_attributes
            get_stack_node_resources
            @nodes.collect { |n| n.attributes }
        end

        def create(index)

            name = "#{@node_id}-#{index}"
            self.create_vm(name, @knife_options)

            knife_cmd = KnifeAttribute::Node::NodeAttributeSet.new
            knife_cmd.name_args = [ name, 'stack_id', @id ]
            knife_cmd.config[:type] = 'override'
            run_knife(knife_cmd)

            knife_cmd = KnifeAttribute::Node::NodeAttributeSet.new
            knife_cmd.name_args = [ name, 'stack_node', @name ]
            knife_cmd.config[:type] = 'override'
            run_knife(knife_cmd)
        end

        def create_vm(name, knife_options)
            raise NotImplemented, 'HostNodeManager.create_vm'
        end

        def process(index, events, attributes, target = nil)
        end

        def delete(index)

            name = "#{@node_id}-#{index}"
            self.delete_vm(name, @knife_options)

            knife_cmd = Chef::Knife::NodeDelete.new
            knife_cmd.name_args = [ name ]
            knife_cmd.config[:yes] = true
            run_knife(knife_cmd)

            knife_cmd = Chef::Knife::ClientDelete.new
            knife_cmd.name_args = [ name ]
            knife_cmd.config[:yes] = true
            run_knife(knife_cmd)
        end

        def delete_vm(name, knife_options)
            raise NotImplemented, 'HostNodeManager.delete_vm'
        end

        private

        def get_stack_node_resources

            query = Chef::Search::Query.new

            escaped_query = URI.escape(
                "stack_id:#{@id} AND stack_node:#{@name}",
                Regexp.new("[^#{URI::PATTERN::UNRESERVED}]") )

            results = query.search('node', escaped_query, nil, 0, 999999)
            @nodes = results[0]

            results[2]
        end
    end
end
