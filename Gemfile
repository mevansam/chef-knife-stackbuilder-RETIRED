# Copyright (c) 2014 Mevan Samaratunga

source 'https://rubygems.org'
gemspec

gem 'rake'

gem 'chef'

gem 'chef-zero'
gem 'berkshelf'
gem 'highline'

gem 'knife-attribute'
gem 'knife-container'
gem 'knife-vagrant3'

group :development, :test do

    gem 'ci_reporter'
    gem 'simplecov'
    gem 'simplecov-rcov'

    gem 'rb-fsevent', :require => false if RUBY_PLATFORM =~ /darwin/i
    gem 'guard-rspec'
    gem 'guard-livereload'
end
