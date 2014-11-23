# Copyright (c) 2014 Mevan Samaratunga

include StackBuilder::Common::Helpers

module StackBuilder::Chef

    class NodeProvider < StackBuilder::Stack::NodeProvider

        def initialize(repo_path, environment)

            @logger = StackBuilder::Common::Config.logger

            @repo_path = File.expand_path(repo_path)
            @environment = environment

            env_file = "#{@repo_path}/etc/#{@environment}.yml"
            if File.exist?(env_file)

                @logger.debug( "Loading externalized environment variables from " +
                  "'#{env_file}' and merging them with the current process environment." )

                @env_vars = YAML.load_file(env_file)
            else
                @env_vars = { }
            end

            merge_maps(@env_vars, ENV)
        end

        def set_stack(stack, id)

            @stack = stack
            @id = id

            stack_environment = stack['environment']
            raise ArgmentError, "Stack file is fixed to the environment '#{stack_environment}', " +
                " which it does not match the environment '#{@environment}' provided." \
                unless stack_environment.nil? || stack_environment==@environment

            Chef::Config[:chef_server_url] = stack['chef_server_url'] if stack.has_key?('chef_server_url')
            Chef::Config[:environment] = @environment
        end

        def get_env_vars
            @env_vars
        end

        def get_node_manager(node_config)

            knife_config = node_config['knife']
            if knife_config.has_key?('plugin')

                case knife_config['plugin']
                    when 'vagrant'
                        return StackBuilder::Chef::VagrantNodeManager.new(@id, node_config, @repo_path, @environment)

                    # TODO: Refactor so that managers are pluggable from other gems

                    else
                        raise ArgumentError, "Unknown plugin #{knife['plugin']}."
                end

            elsif knife_config.has_key?('create')
                return StackBuilder::Chef::GenericNodeManager.new(@id, node_config, @repo_path, @environment)

            else
                return StackBuilder::Chef::NodeManager.new(@id, node_config, @repo_path, @environment)
            end
        end
    end
end