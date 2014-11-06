# Copyright (c) 2014 Mevan Samaratunga

require File.expand_path('../../../spec_helper', __FILE__)

include StackBuilder::Common::Helpers

describe StackBuilder::Stack do

    before(:all) do
        @logger = StackBuilder::Common::Config.logger
    end

    after(:all) do
    end

    it "should initialize a stack file" do

        # Chef::Knife::Search
    end

    it "should orchestrate a stack file" do

    end

end