# Copyright (c) 2014 Mevan Samaratunga

require File.expand_path('../../../spec_helper', __FILE__)

include StackBuilder::Common::Helpers

describe StackBuilder::Stack do

    it "run knife" do

        knife_cmd = Chef::Knife::EnvironmentShow.new
        knife_cmd.name_args = [ 'xxx' ]

        expect {

            run_knife_forked(knife_cmd)

        }.to raise_error(StackBuilder::Common::StackBuilderError)

        knife_cmd = Chef::Knife::ClientList.new
        result = run_knife_forked(knife_cmd)
        puts "Result of 'knife client list' =>\n#{result}"

        expect(result.split(/[\r\n]/)).to include('chef-validator')

        knife_cmd1 = Chef::Knife::ClientList.new
        knife_cmd2 = Chef::Knife::ClientList.new
        results = run_knife_forked(knife_cmd1, knife_cmd2)
        puts "Results of multiple knife cmds => \n#{result}"

        expect(results.size).to eq(2)
    end
end