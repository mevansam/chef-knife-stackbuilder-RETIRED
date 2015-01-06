# Copyright (c) 2014 Mevan Samaratunga

module StackBuilder::Common
    
    class Config

        QUERY_TIMEOUT = 60
        CACHE_TIMEOUT = 60

        class << self
            extend Forwardable
            def_delegators :@delegate, :logger, :timeouts, :enable_caching, :cachedir, :silent
        end

        def self.configure(config)
            
            config.silent = false
            
            # Determine timeouts
            config.timeouts = { } if config.timeouts.nil?
            config.timeouts[:CACHE_TIMEOUT] = CACHE_TIMEOUT unless config.timeouts.has_key?(:CACHE_TIMEOUT)
            config.timeouts[:QUERY_TIMEOUT] = QUERY_TIMEOUT unless config.timeouts.has_key?(:QUERY_TIMEOUT)
            
            # Create cache folder
            config.enable_caching = false if config.enable_caching.nil?
            if config.enable_caching
                config.cachedir = File.expand_path(File.join(Dir.home, ".c2c_cache")) if config.cachedir.nil?
                begin
                    FileUtils.mkdir_p(config.cachedir) if !Dir.exists?(config.cachedir)
                rescue
                    self.logger.debug("could not create cachedir: #{config.cachedir}")
                    config.enable_caching = false
                    config.cachdir = nil
                end
            end
            
            @delegate = config
            
            self.logger.debug("Caching Enabled: #{config.enable_caching}; Cache Dir: #{self.cachedir}; Timeouts: #{self.timeouts}")
        end
        
        def self.set_silent
            @delegate.silent = true
        end
    end
end
