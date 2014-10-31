# Copyright (c) 2014 Mevan Samaratunga

require 'chef/knife/stackbuilder_base'

class Chef
    class Knife

        class StackUploadCookbook < Knife

            include Knife::StackBuilderBase

            deps do
            end

            banner 'knife upload cookbook (options)'

            def run
            end
        end

        class StackUploadCookbooks < Knife

            include Knife::StackBuilderBase

            deps do
            end

            banner 'knife upload cookbooks (options)'

            def run
            end
        end

    end
end
