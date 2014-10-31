# Copyright (c) 2014 Mevan Samaratunga

require File.expand_path('../../../spec_helper', __FILE__)

describe StackBuilder::Chef do

    it "should create a test repository" do

        repo_path = File.expand_path('../../../../tmp/test_repo', __FILE__)
        system("rm -fr #{repo_path}")

        expect {

            # Repo does not exist so it cannot be loaded
            StackBuilder::Chef::Repo.new(repo_path)

        }.to raise_error(StackBuilder::Chef::RepoNotFoundError)

        StackBuilder::Chef::Repo.new(
            repo_path,
            "DEV,TEST,PROD",
            nil,
            "mysql:=5.6.1, wordpress:~> 2.3.0" )
    end
end
