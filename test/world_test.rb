# frozen_string_literal: true

require_relative 'test_helper'
require 'fileutils'
require 'mocha/minitest'

module Dynflow
  module WorldTest
    describe World do
      let(:world) { WorldFactory.create_world }
      let(:world_with_custom_meta) { WorldFactory.create_world { |c| c.meta = { 'fast' => true } } }

      describe '#id' do
        it 'defaults to a random uuid, different for each world' do
          other_world = WorldFactory.create_world
          _(world.id).must_match(/\A[0-9a-f-]{36}\z/)
          _(world.id).wont_equal other_world.id
        end

        it 'is configurable' do
          custom_id = 'my-custom-world-id'
          custom_world = WorldFactory.create_world { |c| c.id = custom_id }
          _(custom_world.id).must_equal custom_id
        end
      end

      describe '#perform_validity_checks' do
        it 'prunes orphaned executor queues' do
          world.executor.expects(:prune_orphaned_queues)
          world.perform_validity_checks
        end

        it 'does not fail when there is no executor' do
          client_world = WorldFactory.create_world { |c| c.executor = false }
          client_world.perform_validity_checks
        end
      end

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
      end
    end
  end
end
