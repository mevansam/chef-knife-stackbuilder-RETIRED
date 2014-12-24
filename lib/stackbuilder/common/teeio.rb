# Copyright (c) 2014 Mevan Samaratunga

module StackBuilder::Common

    #
    # Sends data written to an IO object to multiple outputs.
    #
    class TeeIO < StringIO

        def initialize(output = nil)
            super()
            @output = output
        end

        def write(string)
            super(string)
            @output.write(string) unless @output.nil?
        end
    end
end
