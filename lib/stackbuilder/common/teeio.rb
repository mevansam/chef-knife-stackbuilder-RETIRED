# Copyright (c) 2014 Mevan Samaratunga

module StackBuilder::Common

    #
    # Sends data written to an IO object to multiple outputs.
    #
    class TeeIO < IO

        def initialize(output = nil)
            @string_io = StringIO.new
            @output = output
        end

        def write string
            @string_io.write(string)
            @output.write(string) unless @output.nil?
        end

        def string
            @string_io.string
        end

    end
end
