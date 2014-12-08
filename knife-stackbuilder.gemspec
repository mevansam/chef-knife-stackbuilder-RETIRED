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
    s.homepage     = "https://github.com/mevansam/knife-stackbuilder/wiki"

    #s.files        = `git ls-files -- bin/* lib/*`.split("\n") + %w(README.md Rakefile)
    #s.test_files   = `git ls-files -- spec/*`.split("\n")

    s.files        = `find lib -name '*.rb' -type f -print`.gsub(/\.\//,"").split("\n") + 
                     `find bin -name '*' -type f -print`.gsub(/\.\//,"").split("\n") + 
                     %w(README.md Rakefile)

    s.require_path = "lib"
    s.bindir       = "bin"
    s.executables  = `find bin -name '*' -type f -exec basename {} \\;`.gsub(/\.\//,"").split("\n")

    s.add_dependency("chef", "~> 11.16.4")
    s.add_dependency("knife-attribute", "~> 1.0.3")
    s.add_dependency("highline", "~> 1.6.21")
end
