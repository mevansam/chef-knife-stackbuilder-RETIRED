# Copyright (c) 2014 Mevan Samaratunga

include StackBuilder::Common::Helpers

module StackBuilder::Chef

    class HostNodeManager < StackBuilder::Stack::NodeManager

        include ERB::Util

        attr_accessor :name

        def initialize(id, node_config)

            @logger = StackBuilder::Common::Config.logger

            @id = id
            @name = node_config['node']
            @node_id = @name + '-' + @id

            @run_list = node_config['run_list'].join(',')
            @run_on_event = node_config['run_on_event']

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

            knife_cmd = Chef::Knife::NodeRunListSet.new
            knife_cmd.name_args = [ name, @run_list ]
            run_knife(knife_cmd)
        end

        def create_vm(name, knife_options)
            raise NotImplemented, 'HostNodeManager.create_vm'
        end

        def process(index, events, attributes, target = nil)

            name = "#{@node_id}-#{index}"

            if events.include?('update')
                knife_cmd = Chef::Knife::NodeRunListSet.new
                knife_cmd.name_args = [ name, @run_list ]
                run_knife(knife_cmd)
            end

            set_attributes(name, attributes)

            if events.include?('configure') || events.include?('update')

                log_level = (
                    @logger.level==Logger::FATAL ? 'fatal' :
                    @logger.level==Logger::ERROR ? 'error' :
                    @logger.level==Logger::WARN ? 'warn' :
                    @logger.level==Logger::INFO ? 'info' :
                    @logger.level==Logger::DEBUG ? 'debug' : 'error' )

                knife_ssh(name, 'chef-client -l ' + log_level)
            end

            @run_on_event.each_pair { |event, cmd|
                knife_ssh(name, ERB.new(cmd, nil, '-<>').result(binding)) if events.include?(event) } \
                unless @run_on_event.nil?

        rescue Exception => msg
            puts("Fatal Error processing vm #{name}: #{msg}")
            @logger.info(msg.backtrace.join("\n\t")) if @logger.debug

            raise msg
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

        def set_attributes(name, attributes, key = nil)

            attributes.each do |k, v|

                if v.is_a?(Hash)
                    set_attributes(name, v, key.nil? ? k : key + '.' + k)
                else
                    knife_cmd = KnifeAttribute::Node::NodeAttributeSet.new
                    knife_cmd.name_args = [ name, key + '.' + k, v.to_s ]
                    knife_cmd.config[:type] = 'override'
                    run_knife(knife_cmd)
                end
            end
        end

        def knife_ssh(name, cmd)

            sudo = @knife_options['sudo'] ? 'sudo ' : ''
            ssh_cmd = sudo + cmd

            @logger.debug("Running '#{ssh_cmd}' on node 'name:#{name}'.")

            knife_cmd = Chef::Knife::Ssh.new
            knife_cmd.name_args = [ "name:#{name}", ssh_cmd ]
            knife_cmd.config[:attribute] = 'ipaddress'

            @knife_options.each_pair do |k, v|
                arg = k.gsub(/-/, '_')
                knife_cmd.config[arg.to_sym] = v
            end

            if @logger.info
                output = StackBuilder::Common::TeeIO.new($stdout)
                error = StackBuilder::Common::TeeIO.new($stderr)
                run_knife(knife_cmd, output, error)
            else
                run_knife(knife_cmd)
            end
        end
    end
end
