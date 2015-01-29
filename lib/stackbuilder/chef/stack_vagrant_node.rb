# Copyright (c) 2014 Mevan Samaratunga

include StackBuilder::Common::Helpers

module StackBuilder::Chef

    class VagrantNodeManager < StackBuilder::Chef::NodeManager

        VAGRANT_PROVIDER = 'virtualbox'
        VAGRANT_DIR = File.join(Dir.home, '/.vagrant')
        INSECURE_KEY_PATH = "#{VAGRANT_DIR}/insecure_key"

        def vagrant_version
            @@vagrant_version ||= begin
                `vagrant -v`[/Vagrant\s+([0-9\.]+)/, 1]
            rescue Exception => msg
                raise StackBuilder::Common::StackBuilderError, "Unable to locate vagrant."                
            end
        end

        def get_ssh_credentials(name)

            ssh_user = @knife_config['options']['ssh_user'] || 'vagrant'
            ssh_identity_file = @knife_config['options']['identity_file']

            if ssh_identity_file.nil?

                provider = @knife_config['options']['provider'] || VAGRANT_PROVIDER
                vagrant_dir = @knife_config['options']['vagrant_dir'] || VAGRANT_DIR

                ssh_identity_file = ( vagrant_version<'1.7' ? INSECURE_KEY_PATH : 
                    "#{vagrant_dir}/#{name}/.vagrant/machines/default/#{provider}/private_key" )
            else
                ssh_identity_file.gsub!(/~\//, Dir.home + '/')
            end

            [ ssh_user, nil, ssh_identity_file ]
        end

        def create_vm(index, name, knife_config)

            handle_vagrant_box_additions(name, knife_config)

            knife_cmd = Chef::Knife::VagrantServerCreate.new

            knife_cmd.config[:chef_node_name] = name

            # Set the defaults
            knife_cmd.config[:distro] = 'chef-full'
            knife_cmd.config[:template_file] = false

            knife_cmd.config[:vagrant_dir] = VAGRANT_DIR
            knife_cmd.config[:provider] = VAGRANT_PROVIDER
            knife_cmd.config[:memsize] = 1024
            knife_cmd.config[:subnet] = '192.168.67.0/24'
            knife_cmd.config[:port_forward] = { }
            knife_cmd.config[:share_folders] = [ ]
            knife_cmd.config[:use_cachier] = false

            knife_cmd.config[:host_key_verify] = false
            knife_cmd.config[:ssh_user] = 'vagrant'
            knife_cmd.config[:ssh_port] = '22'

            self.config_knife(name, knife_cmd, knife_config['options'] || { })

            # Let vagrant use auto-generated private key for ssh during bootstrap
            knife_cmd.config[:identity_file] = nil if vagrant_version>'1.7'

            ip_address = knife_cmd.config[:ip_address]
            knife_cmd.config[:ip_address] = ip_address[/(\d+\.\d+\.\d+\.)/, 1] + \
                (ip_address[/\.(\d+)\+/, 1].to_i + name[/-(\d+)$/, 1].to_i).to_s \
                unless ip_address.nil? || !ip_address.end_with?('+')

            @@sync ||= Mutex.new
            @@sync.synchronize {
                run_knife_forked(knife_cmd)
            }
        end

        def delete_vm(name, knife_config)

            knife_cmd = Chef::Knife::VagrantServerDelete.new
            knife_cmd.name_args = [ name ]
            knife_cmd.config[:yes] = true
            knife_cmd.config[:vagrant_dir] = VAGRANT_DIR

            @@sync ||= Mutex.new
            @@sync.synchronize {
                run_knife_forked(knife_cmd)
            }

            handle_vagrant_box_cleanup(knife_config)

        rescue Exception => msg

            if Dir.exist?(knife_cmd.config[:vagrant_dir] + '/' + name)

                knife_cmd = Chef::Knife::VagrantServerList.new
                knife_cmd.config[:vagrant_dir] = File.join(Dir.home, '/.vagrant')
                server_list = run_knife(knife_cmd)

                if server_list.lines.keep_if { |l| l=~/test-TEST-0/ }.first.chomp.end_with?('running')
                    raise msg
                else
                    FileUtils.rm_rf(knife_cmd.config[:vagrant_dir] + '/' + name)
                end
            end
        end

        def config_knife(name, knife_cmd, options)

            super(name, knife_cmd, options)

            # Add ohai plugin to change the ohai ipaddress 
            # value to the non NAT'ed eth1 interface. This
            # is required so you can SSH into vagrant VMs
            # via knife ssh
            ohai_plugin_resource = File.expand_path('../../resources/vagrant.rb', __FILE__)

            knife_cmd.config[:vagrant_config] = \
                "config.vm.provision \"file\", source: \"#{ohai_plugin_resource}\", destination: \"~/vagrant.rb\"::" +
                'config.vm.provision "shell", inline: "mkdir -p /etc/chef/ohai_plugins"::' +
                'config.vm.provision "shell", inline: "mv /home/vagrant/vagrant.rb /etc/chef/ohai_plugins"::' +
                'config.vm.provision "shell", inline: \'echo {\"primary_nic\":\"eth1\"} > /etc/chef/ohai_plugins/vagrant.json\'::' +
                (knife_cmd.config[:vagrant_config] || '')
        end

        def handle_vagrant_box_additions(name, knife_config)

            # Create add-on provider specific infrastructure
            knife_options = knife_config['options']
            provider = knife_options['provider']

            # Create disks for vagrant vms on vmware if requested
            if !provider.nil? && provider.start_with?('vmware')

                vmx_customize = knife_options['vmx_customize']
                unless vmx_customize.nil?

                    # Build additional disks that will be added to
                    # the VMware fusion/desktop VM when booted.

                    disks = {}
                    vagrant_disk_path = File.join(Dir.home, '/.vagrant/disks') + '/' + name
                    FileUtils.mkdir_p(vagrant_disk_path)

                    vmx_customize.split(/::/).each do |p|

                        kv = p.split('=')
                        k = kv[0].gsub(/\"/, '').strip
                        v = kv[1].gsub(/\"/, '').strip

                        if k.start_with?('scsi')
                            ss = k.split('.')
                            disks[ss[0]] ||= {}
                            case ss[1]
                                when 'fileName'
                                    if v.start_with?('/')
                                        disks[ss[0]]['fileName'] = v
                                    else
                                        vv = vagrant_disk_path + '/' + v
                                        vmx_customize.gsub!(/#{v}/, vv)
                                        disks[ss[0]]['fileName'] = vv
                                    end
                                when 'fileSize'
                                    disks[ss[0]]['fileSize'] = v
                            end
                        end
                    end

                    # Create extra disks as unlike virtual box VMware fusion/workstation
                    # will not create disks automatically based on configuration params

                    vdiskmgr = %x(which vmware-vdiskmanager)
                    vdiskmgr = "/Applications/VMware Fusion.app/Contents/Library/vmware-vdiskmanager" \
                        if is_os_x? && vdiskmgr.empty?

                    if File.exist?(vdiskmgr)

                        run_jobs(disks.values) do |f|

                            disk = f['fileName']
                            @logger.info("Creating disk #{disk}.")

                            %x("#{vdiskmgr}" -c -t 0 -s #{f['fileSize']} -a ide #{disk}) \
                                unless File.exist?(f['fileName'])

                            raise StackBuilder::Common::StackBuilderError, "Disk #{disk} could not be created." \
                                unless File.exist?(disk)
                        end
                    else
                        raise StackBuilder::Common::StackBuilderError,
                            "Unable to determine path to vmware-vdiskmanager" +
                            "to create the requested additional disk."
                    end
                end
            end
        end

        def handle_vagrant_box_cleanup(knife_config)
        end
    end
end
