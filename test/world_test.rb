require_relative 'test_helper'
require 'fileutils'

module Dynflow
  module WorldTest
    describe World do
      let(:world) { WorldFactory.create_world }
      let(:world_with_custom_meta) { WorldFactory.create_world { |c| c.meta = { 'fast' => true } } }

      describe '#meta' do
        it 'by default informs about the hostname and the pid running the world' do
          registered_world = world.coordinator.find_worlds(false, id: world.id).first
          registered_world.meta.must_equal('hostname' => Socket.gethostname, 'pid' => Process.pid,
                                           'queues' => { 'default' => { 'pool_size' => 5 }})
        end

        it 'is configurable' do
          registered_world = world.coordinator.find_worlds(false, id: world_with_custom_meta.id).first
          registered_world.meta.must_equal('fast' => true)
        end
      end

      describe '#get_execution_status' do
        let(:base) do
          { :default => { :pool_size => 5, :free_workers => 5, :execution_status => {} }}
        end

        it 'retrieves correct execution items count' do
          world.get_execution_status(world.id, nil, 5).value!.must_equal(base)
          id = 'something like uuid'
          expected = base.dup
          expected[:default][:execution_status] = { id => 0 }
          world.get_execution_status(world.id, id, 5).value!.must_equal(expected)
        end
      end

      describe '#terminate' do
        it 'fires an event after termination' do
          terminated_event = world.terminated
          terminated_event.completed?.must_equal false
          world.terminate
          # wait for termination process to finish, but don't block
          # the test from running.
          terminated_event.wait(10)
          terminated_event.completed?.must_equal true
        end
      end
    end
  end
end
