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
SimpleCov.start

ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../../Gemfile", __FILE__)

require "rubygems"
require "bundler"

Bundler.setup(:default, :test)

require "rspec"
require "tmpdir"
require "net/http"
require "xmlrpc/httpserver"

require "click2compute_api"

$logger = Logger.new(STDOUT)
$logger.level = Logger::WARN

c2c_config = OpenStruct.new(
    :logger => $logger, 
    :enable_caching => false,
    :timeouts => { :ORDER_TIMEOUT=> 1800, :READY_TIMEOUT => 1800, :START_TIMEOUT => 1800, :CACHE_TIMEOUT => 1800 } )

Click2Compute::API::Config.configure(c2c_config)

env = "dev"

c2c_ep_config = YAML.load_file(File.expand_path("../../config/#{env}-cloud-cfg-c2c.yml", __FILE__))
c2c_ep_config["click2compute"]["key_files"] = File.expand_path("../../config/c2c_#{env}_key", __FILE__)
$client ||= Click2Compute::API::Client.new(c2c_ep_config)
