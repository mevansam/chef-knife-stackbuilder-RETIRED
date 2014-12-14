# Copyright (c) 2014 Mevan Samaratunga

include StackBuilder::Common::Helpers

module StackBuilder::Chef

    class NodeManager < StackBuilder::Stack::NodeManager

        include ERB::Util

        attr_accessor :name
        attr_accessor :node_id

        attr_accessor :run_list
        attr_accessor :run_on_event

        attr_accessor :ssh_user
        attr_accessor :ssh_password
        attr_accessor :ssh_identity_file

        def initialize(id, node_config, repo_path, environment)

            @logger = StackBuilder::Common::Config.logger

            @id = id
            @name = node_config['node']
            @node_id = @name + '-' + @id

            @environment = environment

            @run_list = node_config.has_key?('run_list') ? node_config['run_list'].join(',') : nil
            @run_on_event = node_config['run_on_event']

            @knife_config = node_config['knife']
            if @knife_config && @knife_config.has_key?('options')

                raise ArgumentError, 'An ssh user needs to be provided for bootstrap and knife ssh.' \
                    unless @knife_config['options'].has_key?('ssh_user')

                raise ArgumentError, 'An ssh key file or password must be provided for knife to be able ssh to a node.' \
                    unless @knife_config['options'].has_key?('identity_file') ||
                       @knife_config['options'].has_key?('ssh_password')

                @ssh_user = @knife_config['options']['ssh_user']
                @ssh_password = @knife_config['options']['ssh_password']
                @ssh_identity_file = @knife_config['options']['identity_file']
                @ssh_identity_file.gsub!(/~\//, Dir.home + '/') unless @ssh_identity_file.nil?
            end

            @env_key_file = "#{repo_path}/secrets/#{environment}"
            @env_key_file = nil unless File.exist?(@env_key_file)
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
            self.create_vm(name, @knife_config)

            knife_cmd = KnifeAttribute::Node::NodeAttributeSet.new
            knife_cmd.name_args = [ name, 'stack_id', @id ]
            knife_cmd.config[:type] = 'override'
            run_knife(knife_cmd)

            knife_cmd = KnifeAttribute::Node::NodeAttributeSet.new
            knife_cmd.name_args = [ name, 'stack_node', @name ]
            knife_cmd.config[:type] = 'override'
            run_knife(knife_cmd)

            unless @env_key_file.nil?
                env_key = IO.read(@env_key_file)
                knife_ssh( name,
                    "echo '#{env_key}' > /etc/chef/encrypted_data_bag_secret\n" +
                    "chmod 0600 /etc/chef/encrypted_data_bag_secret" )
            end

        rescue Exception => msg
            puts("\nError creating node #{name} using knife config: #{msg}\n#{@knife_config.to_yaml}\n")
            @logger.info(msg.backtrace.join("\n\t")) if @logger.debug

            raise msg
        end

        def create_vm(name, knife_config)
            raise StackBuilder::Common::NotImplemented, 'HostNodeManager.create_vm'
        end

        def process(index, events, attributes, target = nil)

            if target.nil?
                self.process_vm(index, events, attributes)
            else
                target.process_vm(index, events, attributes, self)
            end
        end

        def process_vm(index, events, attributes, node_manager = nil)

            name = "#{@node_id}-#{index}"

            if node_manager.nil?
                run_list = @run_list
                run_on_event = @run_on_event
            else
                run_list = node_manager.run_list
                run_on_event = node_manager.run_on_event
            end

            set_attributes(name, attributes)

            if (events.include?('configure') || events.include?('update')) && !run_list.nil?

                log_level = (
                    @logger.debug? ? 'debug' :
                    @logger.info? ? 'info' :
                    @logger.warn? ? 'warn' :
                    @logger.error? ? 'error' :
                    @logger.fatal? ? 'fatal' : 'error' )

                knife_cmd = Chef::Knife::NodeRunListSet.new
                knife_cmd.name_args = [ name, run_list ]
                run_knife(knife_cmd)

                knife_ssh( name,
                    "TMPFILE=`mktemp`\n" +
                    "echo '#{attributes.to_json}' > $TMPFILE\n" +
                    "chef-client -l #{log_level} -j $TMPFILE\n" +
                    "result=$?\n" +
                    "rm -f $TMPFILE\n" +
                    "exit $result" )
            end

            run_on_event.each_pair { |event, cmd|
                knife_ssh(name, ERB.new(cmd, nil, '-<>').result(binding)) if events.include?(event) } \
                unless run_on_event.nil?

        rescue Exception => msg

            puts( "\nError processing node #{name}: #{msg} " +
                "\nEvents => #{events.collect { |e| e } .join(", ")}" +
                "\nknife config =>\n#{@knife_config.to_yaml}" +
                "\nrun list =>\n#{run_list}" +
                "\nevent scripts =>\n#{run_on_event.to_yaml}\n" )

            @logger.info(msg.backtrace.join("\n\t")) if @logger.debug

            raise msg
        end

        def delete(index)

            name = "#{@node_id}-#{index}"
            self.delete_vm(name, @knife_config)

            knife_cmd = Chef::Knife::NodeDelete.new
            knife_cmd.name_args = [ name ]
            knife_cmd.config[:yes] = true
            run_knife(knife_cmd)

            knife_cmd = Chef::Knife::ClientDelete.new
            knife_cmd.name_args = [ name ]
            knife_cmd.config[:yes] = true
            run_knife(knife_cmd)

        rescue Exception => msg
            puts("\nError deleting node #{name} using knife config: #{msg}\n#{@knife_config.to_yaml}\n")
            @logger.info(msg.backtrace.join("\n\t")) if @logger.debug

            raise msg
        end

        def delete_vm(name, knife_config)
            raise StackBuilder::Common::NotImplemented, 'HostNodeManager.delete_vm'
        end

        def config_knife(knife_cmd, options)

            options.each_pair do |k, v|

                arg = k.gsub(/-/, '_')

                # Fix issue where '~/' is not expanded to home dir
                v.gsub!(/~\//, Dir.home + '/') if arg.end_with?('_dir') && v.start_with?('~/')

                knife_cmd.config[arg.to_sym] = v
            end
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
                    knife_cmd.name_args = [ name, (key.nil? ? k : key + '.' + k), v.to_s ]
                    knife_cmd.config[:type] = 'override'
                    run_knife(knife_cmd)
                end
            end
        end

        def knife_ssh(name, cmd)

            sudo = @knife_config['options']['sudo'] ? 'sudo -i su -c ' : ''

            ssh_cmd = "TMPFILE=`mktemp` && " +
                "echo -e \"#{cmd.gsub(/\"/, "\\\"").gsub(/\$/, "\\$").gsub(/\`/, '\\' + '\`')}\" > $TMPFILE && " +
                "chmod 0744 $TMPFILE && " +
                "#{sudo}$TMPFILE && " +
                "rm $TMPFILE"

            knife_cmd = Chef::Knife::Ssh.new
            knife_cmd.name_args = [ "name:#{name}", ssh_cmd ]
            knife_cmd.config[:attribute] = 'ipaddress'

            config_knife(knife_cmd, @knife_config['options'] || { })

            if @logger.info? || @logger.debug?

                output = StackBuilder::Common::TeeIO.new($stdout)
                error = StackBuilder::Common::TeeIO.new($stderr)

                @logger.info("Running '#{cmd}' on node 'name:#{name}'.")
                run_knife(knife_cmd, 0, output, error)
            else
                run_knife(knife_cmd)
            end
        end

    end
end
