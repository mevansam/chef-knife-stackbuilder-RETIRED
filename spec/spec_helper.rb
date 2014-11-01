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

# server = ChefZero::Server.new(port: 9999, debug: true)
# server.start_background

logger = Chef::Log.logger
logger.level = Logger::ERROR

Chef::Config.from_file(knife_config_file)

config = OpenStruct.new(:logger => logger, :enable_caching => false, :timeouts => { :CACHE_TIMEOUT => 1800 } )
StackBuilder::Common::Config.configure(config)
