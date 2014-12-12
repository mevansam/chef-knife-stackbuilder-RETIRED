## Knife StackBuilder plugin

### Using Chef-Zero for local development

Create a folder which will become your development workspace, and in that folder:

* Setup a script to start Chef-Zero.

	Create File ```run_zero.rb``` and copy the following content to it:

	```
require 'chef_zero/server'
if system("lsof -i:9999", out: '/dev/null')
	puts "Seems like port 9999 is already in use..."
else
	server = ChefZero::Server.new(host: '0.0.0.0', port: 9999, debug: true)
	server.start
end
```

* Create knife configuration files and put them in a default location so you do not need to specify the ```-c [myknife.rb]``` option each time you run knife.

	Create configuration directory and keys by running the following commands:

	```
$ rm -fr .chef
$ mkdir -p .chef
$ ssh-keygen -N "" -f .chef/node.pem
$ ssh-keygen -N "" -f .chef/validator.pem
$ rm -f .chef/*.pub
```	

	Create File ```.chef/knife.rb``` and copy the following content to it:

	```
current_dir = File.dirname(__FILE__)
require "socket"
local_ip = UDPSocket.open {|s| s.connect("8.8.8.8", 1); s.addr.last}
log_level               "info"
chef_server_url         "http://#{local_ip}:9999"
node_name               "stackbuilder_test"
client_key              "#{current_dir}/node.pem"
validation_client_name  "chef-zero_validator"
validation_key          "#{current_dir}/validator.pem"
knife[:berks_knife_config] = __FILE__
```

* Start Chef-Zero in the background from a shell and test connectivity.
	
	```
$ ruby run_zero.rb &
$ knife client list
chef-validator
chef-webui
```

### Create and Build a Stack

Create you first repository and upload it to Chef.

```
$ knife stack initialize repo --repo-path wordpress --cookbooks "wordpress:~> 2.3.0" --stack-environments "dev" 
$ cd wordpress
.
.
$ knife stack upload repo
.
.
```

Build the stack.

```
$ knife stack build stack1 --stack-id alpha --environment dev
```

> If the ```stack-id``` is not provided when building then an UUID will be generated. You can provide your own ```stack-id``` so it is easier to keep track of the stacks you have created.

Delete the stack.

```
$ knife stack delete stack1 --stack-id alpha --environment dev
```

### Troubleshooting the Vagrant Knife plugin

When the Vagrant Knife plugin does not finish bootstrapping a VM it leaves an inconsistent state on your machine that will prevent re-creation of VMs with the same name. For example running ```knife stack build`` may result in an error like:

```
Creating node resource 'stack1-node[0]'.
Instance name: stack1-node-alpha-0
Instance IP: 192.168.50.3
Box: chef/ubuntu-14.04
Knife execution failed with an error.
* StdOut from knife run: 
* StdErr from knife run: ERROR: Instance stack1-node-alpha-0 already exists
```

If this happens you need to manually clean up. First get a list of VMs tracked by the plugin.

```
$ knife vagrant server list --yes --vagrant-dir ~/.vagrant
Instance Name        IP Address    Box                Provider    State
stack1-node-alpha-0  192.168.50.2  chef/ubuntu-14.04  virtualbox  not created
```

Check if these nodes are tracked by Chef.

```
$ knife node list
```

If Chef is not tracking the nodes listed by the Vagrant plugin then you need to delete them.

```
$ knife vagrant server delete stack1-node-alpha-0 --yes --vagrant-dir ~/.vagrant
```

Lastly make sure that a folder for the VM does not exist in the folder where the Vagrant plugin keeps track of the VMs it creates

```
$ ls -l ~/.vagrant
total 8
-rw-------  1 john  staff  1675 Dec  1 23:32 insecure_key
drwxr-xr-x  4 john  staff   136 Dec 11 12:09 stack1-node-alpha-0
```

Remove that folder and rebuild.
