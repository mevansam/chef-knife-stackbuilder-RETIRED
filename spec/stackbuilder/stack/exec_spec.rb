# Copyright (c) 2014 Mevan Samaratunga

require File.expand_path('../../../spec_helper', __FILE__)

include StackBuilder::Common::Helpers

describe StackBuilder::Stack do

    it "run multiple forked jobs and collect the results" do

        jobs = [
            [
                'out-1111',
                'err-1111',
                2
            ],
            [
                'out-2222',
                'err-2222',
                4
            ],
            [
                'out-3333',
                'err-3333',
                2
            ]
        ]

        job_handles = run_jobs(jobs) do |job|
            puts job[0]
            $stderr.puts job[1]
            sleep job[2]
        end

        job_results = wait_jobs(job_handles)

        jobs.each do |job|

            result = job_results[job.object_id]
            expect(result[0].chomp).to eq(job[0])
            expect(result[1].chomp).to eq(job[1])
        end

    end
end