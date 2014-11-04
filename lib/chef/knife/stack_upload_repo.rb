# Copyright (c) 2014 Mevan Samaratunga

require 'chef/knife/stackbuilder_base'

class Chef
    class Knife

        class StackUploadRepo < Knife

            include Knife::StackBuilderBase

            banner "knife stack upload repo REPO_PATH (options)"

            def run
            end
        end

    end
end
