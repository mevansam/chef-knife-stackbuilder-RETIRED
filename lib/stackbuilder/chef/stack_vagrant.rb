# Copyright (c) 2014 Mevan Samaratunga

include StackBuilder::Common::Helpers

module StackBuilder::Chef

    class VagrantNodeManager < StackBuilder::Chef::HostNodeManager

        def create_vm(name, knife_options)

            knife_cmd = Chef::Knife::VagrantServerCreate.new

            knife_cmd.config[:chef_node_name] = name

            # Set the defaults
            knife_cmd.config[:distro] = 'chef-full'
            knife_cmd.config[:template_file] = false

            knife_cmd.config[:vagrant_dir] = File.join(Dir.pwd, '/.vagrant')
            knife_cmd.config[:provider] = 'virtualbox'
            knife_cmd.config[:memsize] = 1024
            knife_cmd.config[:subnet] = '192.168.67.0/24'
            knife_cmd.config[:port_forward] = { }
            knife_cmd.config[:share_folders] = [ ]
            knife_cmd.config[:use_cachier] = false

            knife_cmd.config[:host_key_verify] = false
            knife_cmd.config[:ssh_user] = 'vagrant'
            knife_cmd.config[:ssh_port] = '22'

            # Override above values from options provided in stack file
            knife_options.each_pair do |k, v|

                arg = k.gsub(/-/, '_')
                knife_cmd.config[arg.to_sym] = v
            end

            knife_cmd.config[:vagrant_dir] = File.join(Dir.pwd, '/.vagrant')

            # Vagrant is single threaded
            @sync ||= Mutex.new
            @sync.synchronize {
                run_knife(knife_cmd)
            }

        rescue Exception => msg
            puts(msg.backtrace.join("\n\t"))
            raise msg
        end

        def delete_vm(name, knife_options)

            knife_cmd = Chef::Knife::VagrantServerDelete.new
            knife_cmd.name_args = [ name ]
            knife_cmd.config[:yes] = true
            knife_cmd.config[:vagrant_dir] = File.join(Dir.pwd, '/.vagrant')

            # Vagrant is single threaded
            @sync ||= Mutex.new
            @sync.synchronize {
                run_knife(knife_cmd)
            }

        rescue Exception => msg
            puts(msg.backtrace.join("\n\t"))
            raise msg
        end
    end
end
