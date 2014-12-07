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

                def getConfig(key)
                    key = key.to_sym
                    config[key] || Chef::Config[:knife][key]
                end
            end

        end
    end
end
