# Copyright (c) 2014 Mevan Samaratunga

require File.dirname(__FILE__) + "/lib/stackbuilder/version"

Gem::Specification.new do |s|
    s.name         = "knife-stackbuilder"
    s.version      = Knife::StackBuilder::VERSION
    s.platform     = Gem::Platform::RUBY
    s.summary      = "Knife Stackbuilder plugin"
    s.description  = s.summary
    s.author       = "Mevan Samaratunga"
    s.email        = "mevansam@gmail.com"
    s.homepage     = "https://github.com/mevansam/chef-knife-stackbuilder"

    #s.files        = `git ls-files -- bin/* lib/*`.split("\n") + %w(README.md Rakefile)
    #s.test_files   = `git ls-files -- spec/*`.split("\n")

    s.files        = `find lib -name '*' -type f -print`.gsub(/\.\//,"").split("\n") + 
                     `find bin -name '*' -type f -print`.gsub(/\.\//,"").split("\n") + 
                     %w(README.md Rakefile)

    s.require_path = "lib"
    s.bindir       = "bin"
    s.executables  = `find bin -name '*' -type f -exec basename {} \\;`.gsub(/\.\//,"").split("\n")

    s.add_dependency("chef", "~> 12")
    s.add_dependency("berkshelf", "~> 3.2.1")
    s.add_dependency("knife-attribute")
    s.add_dependency("knife-container")
    s.add_dependency("knife-vagrant2")
    s.add_dependency("highline")
end
