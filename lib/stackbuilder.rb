# Copyright (c) 2014 Mevan Samaratunga

module StackBuilder
    module Common; end
    module Stack; end
end

require 'ostruct'
require 'erb'
require 'securerandom'
require 'fileutils'
require 'tmpdir'
require 'tempfile'
require "stringio"
require 'json'
require 'timeout'
require 'openssl'
require "net/ssh"
require "net/ssh/multi"
require "highline/import"

require 'chef'
require 'chef/knife'
require 'chef/knife/core/bootstrap_context'
require 'chef/knife/core/object_loader'
require 'chef/knife/environment_from_file'
require 'chef/knife/data_bag_list'
require 'chef/knife/data_bag_create'
require 'chef/knife/data_bag_from_file'
require 'chef/knife/role_from_file'
require 'chef/knife/node_run_list_set'
require 'chef/knife/node_delete'
require 'chef/knife/client_delete'
require 'chef/knife/ssh'
require 'chef/knife/search'
require 'chef/knife/bootstrap'
require 'chef/knife/attribute'
require 'chef/knife/vagrant_server_create'
require 'chef/knife/vagrant_server_delete'
require 'chef/knife/vagrant_server_list'
require 'chef/knife/container_docker_init'
require 'chef/knife/container_docker_build'

require 'stackbuilder/common/config'
require 'stackbuilder/common/errors'
require 'stackbuilder/common/helpers'
require 'stackbuilder/common/semaphore'
require 'stackbuilder/common/teeio'
require 'stackbuilder/stack/stack'
require 'stackbuilder/stack/node_task'
require 'stackbuilder/stack/node_provider'
require 'stackbuilder/stack/node_manager'
require 'stackbuilder/chef/repo'
require 'stackbuilder/chef/stack_provider'
require 'stackbuilder/chef/stack_node_manager'
require 'stackbuilder/chef/stack_vagrant_node'
require 'stackbuilder/chef/stack_generic_node'
require 'stackbuilder/chef/stack_container_node'
