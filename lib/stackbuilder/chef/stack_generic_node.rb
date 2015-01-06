# Copyright (c) 2014 Mevan Samaratunga

include StackBuilder::Common::Helpers

module StackBuilder::Chef

    class GenericNodeManager < StackBuilder::Chef::NodeManager

        def create_vm(index, name, knife_config)

            create_class_name = knife_config['create']['class']
            raise ArgumentError, "Knife plugin's server 'create' class name not provided." \
                if create_class_name.nil?

            knife_cmd = eval(create_class_name + '.new')

            if knife_config['create'].has_key?('name_key')
                name_key = knife_config['create']['name_key']
                knife_cmd.config[name_key.to_sym] = name
            else
                knife_cmd.name_args = [ name ]
            end

            if knife_config['create'].has_key?('pool_key')

                pool_key = knife_config['create']['pool_key']

                placement_pools = knife_config['placement_pools']
                raise ArgumentError, "Knife plugin 'placement_pools' list was not provided." \
                    if placement_pools.nil?

                knife_cmd.config[pool_key.to_sym] = placement_pools[index % placement_pools.size]
            end            

            config_knife(knife_cmd, knife_config['create']['options'] || { })
            config_knife(knife_cmd, knife_config['options'] || { })

            if knife_config['create']['synchronized']
                @@sync ||= Mutex.new
                @@sync.synchronize {
                    run_knife(knife_cmd, knife_config['create']['retries'] || 0)
                }
            else
                run_knife(knife_cmd, knife_config['create']['retries'] || 0)
            end
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

            config_knife(knife_cmd, knife_config['delete']['options'] || { })
            config_knife(knife_cmd, knife_config['options'] || { })

            knife_cmd.config[:yes] = true

            if knife_config['delete']['synchronized']
                @@sync ||= Mutex.new
                @@sync.synchronize {
                    run_knife(knife_cmd, knife_config['delete']['retries'] || 0)
                }
            else
                run_knife(knife_cmd, knife_config['delete']['retries'] || 0)
            end
        end
    end
end
