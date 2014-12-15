# Knife StackBuilder plugin

Knife StackBuilder is a Chef Knife tool that can be used to orchestrate configuration across multiple nodes. It
evolved from the need to simplify using Chef to build a clustered application services environment such as OpenStack.
The plugin was built to:

1. Describe a complex system topology using a YAML file
2. Leverage knife cloud plugins to bootstrap cloud, virtual and baremetal nodes within the topology
3. Leverage knife container to build and deploy docker containers using Chef cookbooks
4. Re-use cookbooks from the [Chef Supermarket](http://supermarket.getchef.com)
5. Leverage the Berkshelf workflow and not re-invent the wheel for developing Chef cookbooks
6. Normalize the Chef environment and provide a means to externalize and parameterize configuration values

The plugin is very similar to Ansible and Saltstack, but is meant to be Chef centric. It you plan is to not use Chef
cookbooks for configuration management, then this is not the tool for you. It differs from Chef metal in that the
orchestration is driven by a set of directives captured as a YAML file. The advantage of describing the build in a
YAML file is that it is easier to transform the topology description to another format such as Heat or Bosh if a
decision is made down the road to move to a different infrastructure orchestration approach.

Check out the brief [tutorial](docs/how-to.md) on setting up a repository for a single node wordpress stack and building
it. The [OpenStack HA Cookbook](https://github.com/mevansam/openstack-ha-cookbook) contains examples where the plugin
is used to setup mult-node OpenStack environments in Vagrant, VMware etc. using the OpenStack StackForge cookbooks.

## Overview

The plugin extends the standard cookbook repository upload capabilities to provide an extensive variable substituion
capability. This is done to enable templatizing the Chef artifacts to model a system which can be manipulated by
variables in environment specific YAML files in the '```etc/```' folder which in turn can be overridden by shell
variables.

### Chef and Berkshelf Cookbook Repository Management

This is nothing more than a wrapper of existing Chef and Berkshelf repository functionality. However, it adds a couple
of key features that are helpful when externalizing and securing the environment for Chef.

* Cookbooks

    '```knife stack upload cookbooks```' simply invokes Berkshelf to upload the cookbooks specified in the Berksfile.

* Data Bags and Encryption

    '```knife stack upload data bags```' will upload the data bags found within the '```data_bags/```' folder. Folders
    at the top-level of that folder will considered to be the data bags with the json files within them, the data bag
    item and its content. A data bag instance will be created for each environment and encrypted with an environment
    specific key found in the '```secrets/```' folder. So a data bag name will have the format '```[data bag
    name]-[environment]```'.

    Data bag content can be parameterized with the environment specific YAML file in the '```etc/```' folder. This
    simplifies the handling of environment specific settings/secrets by externalizing them. Within a data bag folder
    creating a content file within an environment specific folder will override any item content at the parent level.

* Roles

    '```knife stack upload roles```' will upload the roles within the '```roles/```'. This is similar to uploading
    roles via the standard knife role method. However if required, role content can be paremeterized by referencing
    shell environment variables.

### Externalizing configuration values and order of evaluation

As mentioned previously this plugin parameterizes the Chef environment in the '```environments/```' folder using a YAML
file having the same name as the environment in the '```etc/```' folder. This same file is used to parameterize the
stack file that describe the system topology. The YAML environment file can in turn be parameterized by pulling in
values from the shell environment

For example the following will propagate a value from the shell to the rest of the stack and Chef envrionment. Since ruby string variable expansion is used it is possible to reference '```ENV```' to pull shell environment directly into any YAML or JSON configuration file. You can reference a key-value in the yaml that has already been parsed via '```#{my['some key']}```'.

In shell:

```
export DOMAIN=knife-stackbuilder-dev.org
```

in ```./etc/DEV.yml```:

```
---
domain: "#{ENV['DOMAIN']}"
.
.
```

in ```./stack.yml```:

```
---
# Stack
name: Stack1
environment: DEV
domain: "#{env['domain']}"
.
.
```

in ```environments/DEV.rb```:

```
---
name "DEV"
description "Chef 'DEV' environment."
env = YAML.load_file(File.expand_path('../../etc/DEV.yml', __FILE__))
override_attributes(
    'domain' => "#{env['domain']}",
.
.
```

The following diagram illustrates the relationships between the files in the repository and how they are
parameterized.

![Image of OpenStack HA Configuration File Structure]
(docs/images/config_files.png)

#### Requesting user input for non-persisted values



#### Including common yaml configurations

#### Processing node attributes

### Converging a cluster using target nodes

* Magic variables

### Dependency management and orchestration

## To Do:

* Use Chef Pushy instead of Knife SSH and add option to execute Chef Push jobs on events
* Make encrypted data bag handling more robust using Use Chef Vault
* The repo needs to detect changes to cookbooks, roles, data bags etc and upload only the changes
* Load custom provider gems by inspecting the installed gems

## Contributing

1. Fork the repository on Github
2. Write your change
3. Write tests for your change (if applicable)
4. Run the tests, ensuring they all pass
5. Submit a Pull Request

## License and Authors

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

Author | Email | Company
-------|-------|--------
Mevan Samaratunga | msamaratunga@pivotal.io | [Pivotal](http://www.pivotal.io)

