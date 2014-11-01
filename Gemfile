# Copyright (c) 2014 Mevan Samaratunga

source 'https://rubygems.org'
gemspec

gem 'rake'

gem 'chef', '>= 0.11'
gem 'chef-zero'
gem 'berkshelf'
gem 'highline'

group :development, :test do

    gem 'ci_reporter'
    gem 'simplecov'
    gem 'simplecov-rcov'

    gem 'rb-fsevent', :require => false if RUBY_PLATFORM =~ /darwin/i
    gem 'guard-rspec'
    gem 'guard-livereload'
end

group :development do
    gem 'byebug'
end
