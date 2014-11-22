# Copyright (c) 2014 Mevan Samaratunga

require 'simplecov'
require 'simplecov-rcov'

class SimpleCov::Formatter::MergedFormatter
    def format(result)
        SimpleCov::Formatter::HTMLFormatter.new.format(result)
        SimpleCov::Formatter::RcovFormatter.new.format(result)
    end
end

SimpleCov.formatter = SimpleCov::Formatter::MergedFormatter
SimpleCov.start do
    coverage_dir File.expand_path('../../coverage', __FILE__)
end

ENV['BUNDLE_GEMFILE'] ||= File.expand_path('../../Gemfile', __FILE__)

require 'rubygems'
require 'bundler'
Bundler.setup(:default, :test)

require 'rspec'
require 'chef_zero/server'

knife_config_file = File.expand_path('../data/chef-zero_knife.rb', __FILE__)
ENV['BERKSHELF_CHEF_CONFIG'] = knife_config_file

require 'stackbuilder'

require 'chef/knife/environment_show'
require 'chef/knife/data_bag_show'
require 'chef/knife/cookbook_list'
require 'chef/knife/role_list'
require 'chef/knife/role_show'
require 'chef/knife/node_list'
require 'chef/knife/node_show'
require 'chef/knife/client_list'
require 'chef/knife/status'

require 'chef/knife/stack_build'
require 'chef/knife/stack_delete'
require 'chef/knife/stack_initialize_repo'
require 'chef/knife/stack_upload_certificates'
require 'chef/knife/stack_upload_cookbooks'
require 'chef/knife/stack_upload_data_bags'
require 'chef/knife/stack_upload_environments'
require 'chef/knife/stack_upload_repo'
require 'chef/knife/stack_upload_roles'

unless system("lsof -i:9999", out: '/dev/null')
    server = ChefZero::Server.new(host: '0.0.0.0', port: 9999, debug: true)
    server.start_background
end

Chef::Config.from_file(knife_config_file)
logger = Chef::Log.logger
logger.level = Logger::INFO

config = OpenStruct.new(:logger => logger, :enable_caching => false, :timeouts => { :CACHE_TIMEOUT => 1800 } )
StackBuilder::Common::Config.configure(config)

# See http://ruby-doc.org/stdlib-2.1.5/libdoc/net/http/rdoc/Net/HTTP.html
def http_fetch(uri_str, limit = 10)
    # You should choose a better exception.
    raise ArgumentError, 'too many HTTP redirects' if limit == 0

    response = Net::HTTP.get_response(URI(uri_str))

    case response
        when Net::HTTPSuccess then
            response
        when Net::HTTPRedirection then
            location = response['location']
            warn "redirected to #{location}"
            http_fetch(location, limit - 1)
        else
            response.value
    end
end
