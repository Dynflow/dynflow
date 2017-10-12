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
                                           'queues' => { 'default' => { 'pool_size' => 5 },
                                                         'slow' => { 'pool_size' => 1 }})
        end

        it 'is configurable' do
          registered_world = world.coordinator.find_worlds(false, id: world_with_custom_meta.id).first
          registered_world.meta['fast'].must_equal true
        end
      end

      describe '#get_execution_status' do
        let(:base) do
          { :default => { :pool_size => 5, :free_workers => 5, :execution_status => {} },
            :slow => { :pool_size=> 1, :free_workers=> 1, :execution_status=> {}} }
        end

        it 'retrieves correct execution items count' do
          world.get_execution_status(world.id, nil, 5).value!.must_equal(base)
          id = 'something like uuid'
          expected = base.dup
          expected[:default][:execution_status] = { id => 0 }
          expected[:slow][:execution_status] = { id => 0 }
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

      describe '#announce' do
        include TestHelpers

        let(:persistence_adapter) { WorldFactory.persistence_adapter }
        let(:shared_connector) { Connectors::Direct.new() }
        let(:connector) { Proc.new { |world| shared_connector.start_listening(world); shared_connector } }
        let(:announce_world) do
          create_world(false) { |config| config.announce = true }
        end
        let(:world) { create_world(false) }

        it 'announces its availability on creation' do
          # The test worlds are set not to announce themselves
          world

          # Force creation of another world
          announce_world

          # Both world should have each other's records in cache when the messages get delivered
          wait_for do
            cache = world.client_dispatcher.ask!(:ping_cache)
            announce_cache = announce_world.client_dispatcher.ask!(:ping_cache)
            cache.fresh_record?(announce_world.id) &&
              announce_cache.fresh_record?(world.id)
          end
        end
      end
    end
  end
end
