# Copyright (c) 2014 Mevan Samaratunga

class Chef
    class Knife

        module StackBuilderBase

            def self.included(includer)

                includer.class_eval do

                    deps do
                        require 'stackbuilder'

                        config = OpenStruct.new(
                            :logger => Chef::Log.logger,
                            :enable_caching => false,
                            :timeouts => { :CACHE_TIMEOUT => 1800 } )

                        StackBuilder::Common::Config.configure(config)
                    end
                end
            end

            def get_repo_path(name_args)
                unless name_args.size == 1
                    puts "You need specify the path of the repo to create!"
                    show_usage
                    exit 1
                end

                repo_path = name_args.first
            end

        end
    end
end
