# Copyright (c) 2014 Mevan Samaratunga

require 'chef/knife/stackbuilder_base'

class Chef
    class Knife

        class StackUploadRole < Knife

            include Knife::StackBuilderBase

            deps do
            end

            banner "knife stack upload role (options)"

            def run
            end
        end

        class StackUploadRoles < Knife

            include Knife::StackBuilderBase

            deps do
            end

            banner "knife stack upload roles (options)"

            def run
            end
        end

    end
end
