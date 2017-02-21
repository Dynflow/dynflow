require_relative 'test_helper'
require 'active_job'
require 'dynflow/active_job/queue_adapter'

module Dynflow
  class SampleJob < ::ActiveJob::Base
    def perform(msg)
      puts "This job says #{msg}"
    end
  end

  describe 'running jobs' do
    before(:all) do
      world = WorldFactory.create_world
      ::ActiveJob::QueueAdapters.include(::Dynflow::ActiveJob::QueueAdapters)
      ::ActiveJob::Base.queue_adapter = :dynflow
      dynflow_mock = Minitest::Mock.new
      dynflow_mock.expect(:world, world)
      rails_app_mock = Minitest::Mock.new
      rails_app_mock .expect(:dynflow, dynflow_mock)
      rails_mock = Minitest::Mock.new
      rails_mock.expect(:application, rails_app_mock)
      ::Rails = rails_mock
    end

    it 'is able to run the job right away' do
      out, = capture_subprocess_io do
        SampleJob.perform_now 'hello'
      end
      assert_match(/job says hello/, out)
    end

    it 'enqueues the job' do
      out, = capture_subprocess_io do
        SampleJob.perform_later 'hello'
      end
      assert_match(/Enqueued Dynflow::SampleJob/, out)
    end

    it 'schedules job in the future' do
      out, = capture_subprocess_io do
        SampleJob.set(:wait => 1.seconds).perform_later 'hello'
      end
      assert_match(/Enqueued Dynflow::SampleJob.*at.*UTC/, out)
    end
  end
end

