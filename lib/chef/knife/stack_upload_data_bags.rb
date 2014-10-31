# Copyright (c) 2014 Mevan Samaratunga

require 'chef/knife/stackbuilder_base'

class Chef
    class Knife

        class StackUploadDataBag < Knife

            include Knife::StackBuilderBase

            deps do
            end

            banner "knife stack upload data bag (options)"

            def run
            end
        end

        class StackUploadDataBags < Knife

            include Knife::StackBuilderBase

            deps do
            end

            banner "knife stack upload data bags (options)"

            def run
            end
        end

    end
end
