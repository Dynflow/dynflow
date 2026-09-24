# frozen_string_literal: true

require_relative 'test_helper'
require 'fileutils'
require 'mocha/minitest'

module Dynflow
  module WorldTest
    describe World do
      let(:world) { WorldFactory.create_world }
      let(:world_with_custom_meta) { WorldFactory.create_world { |c| c.meta = { 'fast' => true } } }

      describe '#meta' do
        it 'by default informs about the hostname and the pid running the world' do
          registered_world = world.coordinator.find_worlds(false, id: world.id).first
          registered_world.meta.delete('last_seen')
          _(registered_world.meta).must_equal('hostname' => Socket.gethostname, 'pid' => Process.pid,
                                              'queues' => { 'default' => { 'pool_size' => 5 },
                                                            'slow' => { 'pool_size' => 1 } })
        end

        it 'is configurable' do
          registered_world = world.coordinator.find_worlds(false, id: world_with_custom_meta.id).first
          _(registered_world.meta['fast']).must_equal true
        end
      end

      describe '#get_execution_status' do
        let(:base) do
          { :default => { :pool_size => 5, :free_workers => 5, :queue_size => 0 },
            :slow => { :pool_size => 1, :free_workers => 1, :queue_size => 0 } }
        end

        it 'retrieves correct execution items count' do
          _(world.get_execution_status(world.id, nil, 5).value!).must_equal(base)
          id = 'something like uuid'
          expected = base.dup
          expected[:default][:queue_size] = 0
          expected[:slow][:queue_size] = 0
          _(world.get_execution_status(world.id, id, 5).value!).must_equal(expected)
        end
      end

      describe '#terminate' do
        it 'fires an event after termination' do
          terminated_event = world.terminated
          _(terminated_event.resolved?).must_equal false
          world.terminate
          # wait for termination process to finish, but don't block
          # the test from running.
          terminated_event.wait(10)
          _(terminated_event.resolved?).must_equal true
        end

        it 'finishes when the global IO executor is saturated' do
          io_executor = Concurrent::FixedThreadPool.new(1)
          io_started = Concurrent::Event.new
          io_release = Concurrent::Event.new
          saturated_world = WorldFactory.create_world { |config| config.termination_timeout = 0.1 }
          blocker = Concurrent::Promises.future_on(io_executor) do
            io_started.set
            io_release.wait
          end
          assert io_started.wait(1)
          Concurrent.stubs(:global_io_executor).returns(io_executor)

          termination = saturated_world.terminate

          assert termination.wait(1)
          _(saturated_world.terminated.resolved?).must_equal true
        ensure
          io_release&.set
          blocker&.wait(1)
          io_executor&.shutdown
          io_executor&.wait_for_termination(10)
        end
      end
    end
  end
end
