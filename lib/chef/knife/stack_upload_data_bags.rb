# Copyright (c) 2014 Mevan Samaratunga

require 'chef/knife/stackbuilder_base'

class Chef
    class Knife

        class StackUploadDataBag < Knife

            include Knife::StackBuilderBase

            deps do
            end

            banner "knife stack .."

            def run
            end
        end

        class StackUploadDataBags < Knife
        end

    end
end
