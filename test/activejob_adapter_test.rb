# frozen_string_literal: true

require_relative 'test_helper'
require 'active_job'
require 'dynflow/active_job/queue_adapter'

module Dynflow
  class SampleJob < ::ActiveJob::Base
    queue_as :slow

    def perform(msg)
      puts "This job says #{msg}"
      puts "provider_job_id is #{provider_job_id}"
    end
  end

  describe 'running jobs' do
    include TestHelpers

    let :world do
      WorldFactory.create_world
    end

    before(:all) do
      ::ActiveJob::QueueAdapters.send(:include, ::Dynflow::ActiveJob::QueueAdapters)
      ::ActiveJob::Base.queue_adapter = :dynflow
      dynflow_mock = Minitest::Mock.new
      dynflow_mock.expect(:world, world)
      rails_app_mock = Minitest::Mock.new
      rails_app_mock .expect(:dynflow, dynflow_mock)
      rails_mock = Minitest::Mock.new
      rails_mock.expect(:application, rails_app_mock)
      if defined? ::Rails
        @original_rails = ::Rails
        Object.send(:remove_const, 'Rails')
      end
      Object.const_set('Rails', rails_mock)
    end

    after(:all) do
      Object.send(:remove_const, 'Rails')
      Object.const_set('Rails', @original_rails)
    end

    it 'is able to run the job right away' do
      out, = capture_subprocess_io do
        SampleJob.perform_now 'hello'
      end
      assert_match(/job says hello/, out)
    end

    it 'enqueues the job' do
      job = nil
      out, = capture_subprocess_io do
        job = SampleJob.perform_later 'hello'
        wait_for do
          plan = world.persistence.load_execution_plan(job.provider_job_id)
          plan.state == :stopped
        end
      end
      assert_match(/Enqueued Dynflow::SampleJob/, out)
      assert_match(/provider_job_id is #{job.provider_job_id}/, out)
    end

    it 'schedules job in the future' do
      job = nil
      out, = capture_subprocess_io do
        job = SampleJob.set(:wait => 1.seconds).perform_later 'hello'
      end
      assert world.persistence.load_execution_plan(job.provider_job_id)
      assert_match(/Enqueued Dynflow::SampleJob.*at.*UTC/, out)
    end
  end
end
