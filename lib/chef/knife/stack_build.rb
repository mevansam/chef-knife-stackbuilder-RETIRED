# Copyright (c) 2014 Mevan Samaratunga

require 'chef/knife/stackbuilder_base'

class Chef
    class Knife

        class StackBuild < Knife

            include Knife::StackBuilderBase

            deps do
            end

            banner 'knife stack build REPO_PATH (options)'

            def run
            end
        end

    end
end
