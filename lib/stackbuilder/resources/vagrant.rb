Ohai.plugin(:Vboxipaddress) do

    provides "ipaddress"
    depends "ipaddress", "network/interfaces", "virtualization/system", "etc/passwd"

    Chef::Log.info("Running Vagrant plugin to reset node ipaddress attribute.")

    if File.exist?('/etc/chef/ohai_plugins/vagrant.json')
        vagrant = JSON.parse(IO.read('/etc/chef/ohai_plugins/vagrant.json'))

        collect_data(:default) do
            if virtualization["system"] == "vbox" || virtualization["system"] == "vmware"
                if etc["passwd"].any? { |k,v| k == "vagrant"}
                    primary_nic = vagrant["primary_nic"]
                    if primary_nic && network["interfaces"][primary_nic]
                        network["interfaces"][primary_nic]["addresses"].each do |ip, params|
                            if params['family'] == ('inet')
                                Chef::Log.info("Setting node ipaddress attribute to: #{ip}")
                                ipaddress ip
                            end
                        end
                    end
                end
            end
        end
    end
end