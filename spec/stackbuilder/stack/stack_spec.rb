# Copyright (c) 2014 Mevan Samaratunga

require File.expand_path('../../../spec_helper', __FILE__)

include StackBuilder::Common::Helpers

describe StackBuilder::Stack do

    class NodeBuilderTask < NodeTask

    end

    class MockNodeProvider < NodeProvider

        def initialize

            nodes = { }
        end

        def set_stack_id(id, new = true)

        end

        def get_node_task(node_config)

        end
    end

    before(:all) do
        @logger = StackBuilder::Common::Config.logger
    end

    after(:all) do
    end

    it "should initialize a stack file" do


    end

    it "should orchestrate a stack file" do

    end

end