# Copyright (c) 2014 Mevan Samaratunga

include StackBuilder::Common::Helpers

module StackBuilder::Chef

    class GenericNodeManager < StackBuilder::Chef::NodeManager

        def initialize(id, node_config, repo_path, environment, static_ips)

            super(id, node_config, repo_path, environment)

            @static_ips = static_ips
            unless @static_ips.nil?
                get_stack_node_resources
                @nodes.each { |n| @static_ips.delete_if { |ip| ip.split('/').first==n["ipaddress"] } }
            end
        end

        def create_vm(index, name, knife_config)

            pre_create = knife_config['pre_create']
            pre_create.each { |c| self.run_knife_cmd(name, knife_config, c) } unless pre_create.nil?

            create_class_name = knife_config['create']['class']
            raise ArgumentError, "Knife plugin's server 'create' class name not provided." \
                if create_class_name.nil?

            knife_cmd = eval(create_class_name + '.new')

            create_options = knife_config['create']

            if create_options.has_key?('name_key')
                name_key = create_options['name_key']
                knife_cmd.config[name_key.to_sym] = name
            else
                knife_cmd.name_args = [ name ]
            end

            if create_options.has_key?('pool_key')

                pool_key = create_options['pool_key']

                placement_pools = knife_config['placement_pools']
                raise ArgumentError, "Knife plugin 'placement_pools' list was not provided." \
                    if placement_pools.nil?

                knife_cmd.config[pool_key.to_sym] = placement_pools[index % placement_pools.size]
            end

            self.config_knife(name, knife_cmd, knife_config['create']['options'] || { })
            self.config_knife(name, knife_cmd, knife_config['options'] || { })

            if create_options.has_key?('static_ip_key') && !@static_ips.nil?

                static_ip = @static_ips.shift
                raise Common::StackBuilder::StackBuilderError, "Static IP pool is empty." \
                    if static_ip.nil?

                static_ip_key = create_options['static_ip_key']
                ip_data = knife_config['create']['options'][static_ip_key]
                static_ip += "#{ip_data}" unless ip_data.nil?
                
                knife_cmd.config[static_ip_key.to_sym] = static_ip
            end

            @logger.info("Executing knife to create VM: #{knife_cmd} / #{knife_cmd.name_args} / #{knife_cmd.config}")

            if knife_config['create']['synchronized']
                @@sync ||= Mutex.new
                @@sync.synchronize {
                    run_knife_forked(knife_cmd)
                }
            else
                run_knife_forked(knife_cmd)
            end

            post_create = knife_config['post_create']
            post_create.each { |c| self.run_knife_cmd(name, knife_config, c) } unless post_create.nil?
        end

        def run_knife_cmd(name, knife_config, knife_command)

            class_name = knife_command['class']
            raise ArgumentError, "Knife command action class name not provided: #{knife_command}" \
                if class_name.nil?

            knife_cmd = eval(class_name + '.new')

            if knife_command.has_key?('name_key')
                name_key = knife_command['name_key']
                knife_cmd.config[name_key.to_sym] = name
            else
                knife_cmd.name_args = [ name ]
            end

            name_args = knife_command['args'].to_s
            knife_cmd.name_args += name_args.start_with?('"') ?
                name_args.split(/\"\s+\"/).collect { |s| s.gsub(/^\"|\"$/, '') } : name_args.split unless name_args.nil?

            self.config_knife(name, knife_cmd, knife_command['options'] || { })
            self.config_knife(name, knife_cmd, knife_config['options'] || { })

            @logger.info("Executing knife: #{knife_cmd} / #{knife_cmd.name_args} / #{knife_cmd.config}")
            run_knife_forked(knife_cmd)
        end

        def delete_vm(name, knife_config)

            return unless knife_config.has_key?('delete')

            delete_class_name = knife_config['delete']['class']
            raise ArgumentError, "Knife plugin's server 'delete' class name not provided." \
                if delete_class_name.nil?

            knife_cmd = eval(delete_class_name + '.new')

            if knife_config['delete'].has_key?('name_key')
                name_key = knife_config['create']['name_key']
                knife_cmd.config[name_key.to_sym] = name
            else
                knife_cmd.name_args = [ name ]
            end

            self.config_knife(name, knife_cmd, knife_config['delete']['options'] || { })
            self.config_knife(name, knife_cmd, knife_config['options'] || { })

            knife_cmd.config[:yes] = true

            @logger.info("Executing knife to delete VM: #{knife_cmd} / #{knife_cmd.name_args} / #{knife_cmd.config}")

            if knife_config['delete']['synchronized']
                @@sync ||= Mutex.new
                @@sync.synchronize {
                    run_knife_forked(knife_cmd)
                }
            else
                run_knife_forked(knife_cmd)
            end
        end
    end
end
