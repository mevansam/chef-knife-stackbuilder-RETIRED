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

ENV['BUNDLE_GEMFILE'] ||= File.expand_path('../Gemfile', __FILE__)

require 'rubygems'
require 'bundler'
Bundler.setup(:default, :test)

require 'rspec'
require 'chef/config'

require 'stackbuilder'