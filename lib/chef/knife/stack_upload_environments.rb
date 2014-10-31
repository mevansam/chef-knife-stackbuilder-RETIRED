# Copyright (c) 2014 Mevan Samaratunga

require 'chef/knife/stackbuilder_base'

class Chef
    class Knife

        class StackUploadEnvironment < Knife

            include Knife::StackBuilderBase

            deps do
            end

            banner "knife stack upload environment (options)"

            def run
            end
        end

        class StackUploadEnvironments < Knife

            include Knife::StackBuilderBase

            deps do
            end

            banner "knife stack upload environments (options)"

            def run
            end
        end

    end
end
