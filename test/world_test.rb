# frozen_string_literal: true

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

      describe '#chain' do
        it 'chains two execution plans' do
          plan1 = world.plan(Support::DummyExample::Dummy)
          plan2 = world.chain(plan1.id, Support::DummyExample::Dummy)

          preexisting = world.persistence.find_ready_delayed_plans(Time.now).map(&:execution_plan_uuid)

          done = Concurrent::Promises.resolvable_future
          world.execute(plan1.id, done)
          done.wait

          plan1 = world.persistence.load_execution_plan(plan1.id)
          _(plan1.state).must_equal :stopped
          ready = world.persistence.find_ready_delayed_plans(Time.now).reject { |p| preexisting.include? p.execution_plan_uuid }
          _(ready.count).must_equal 1
          _(ready.first.execution_plan_uuid).must_equal plan2.execution_plan_id
        end
      end
    end
  end
end
