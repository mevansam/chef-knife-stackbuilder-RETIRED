# Copyright (c) 2014 Mevan Samaratunga

module StackBuilder::Common

    class StackBuilderError < StandardError; end
    class InvalidArgs < StackBuilderError; end
    class NotImplemented < StackBuilderError; end
    class NotSupported < StackBuilderError; end

    class StackCreateError < StackBuilderError; end
    class StackOrchestrateError < StackBuilderError; end
    class StackDeleteError < StackBuilderError; end

    class CertificateError < StackBuilderError; end

    class KnifeError < StackBuilderError; end
    class BerksError < StackBuilderError; end
end
