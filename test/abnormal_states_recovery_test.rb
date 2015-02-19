# -*- coding: utf-8 -*-
require_relative 'test_helper'

module Dynflow
  module ConsistencyCheckTest

    describe "consistency check" do

      include TestHelpers

      def with_invalidation_while_executing(finish)
        triggered = while_executing_plan do |executor|
          if Connectors::Direct === executor.connector
            # for better simulation of invalidation with direct executor
            executor.connector.stop_listening(executor)
          end
          client_world.invalidate(executor.registered_world)
        end
        plan = if finish
                 finish_the_plan(triggered)
               else
                 triggered.finished.wait
                 client_world.persistence.load_execution_plan(triggered.id)
               end
        yield plan
      ensure
        # just to workaround state transition checks due to our simulation
        # of second world being inactive
        if plan
          plan.set_state(:running, true)
          plan.save
        end
      end

      let(:persistence_adapter) { WorldFactory.persistence_adapter }
      let(:shared_connector) { Connectors::Direct.new() }
      let(:connector) { Proc.new { |world| shared_connector.start_listening(world); shared_connector } }
      let(:executor_world) { create_world(true) }
      let(:executor_world_2) { create_world(true) }
      let(:client_world) { create_world(false) }
      let(:client_world_2) { create_world(false) }

      describe "for plans assigned to invalid world" do

        before do
          # mention the executors to make sure they are initialized
          [executor_world, executor_world_2]
        end

        describe 'world invalidation' do
          it 'removes the world from the register' do
            client_world.invalidate(executor_world.registered_world)
            worlds = client_world.coordinator.find_worlds
            refute_includes(worlds, executor_world.registered_world)
          end

          it 'schedules the plans to be run on different executor' do
            with_invalidation_while_executing(true) do |plan|
              assert_plan_reexecuted(plan)
            end
          end

          it 'when no executor is available, marks the plans as paused' do
            executor_world_2.terminate.wait
            with_invalidation_while_executing(false) do |plan|
              plan.state.must_equal :paused
              plan.result.must_equal :pending
              expected_history = [['start execution', executor_world.id],
                                  ['terminate execution', executor_world.id]]
              plan.execution_history.map { |h| [h.name, h.world_id] }.must_equal(expected_history)
            end
          end

          it "prevents from running the invalidation twice on the same world" do
            client_world.invalidate(executor_world.registered_world)
            expected_locks = ["lock world-invalidation:#{executor_world.id}",
                              "unlock world-invalidation:#{executor_world.id}"]
            client_world.coordinator.adapter.lock_log.must_equal(expected_locks)
          end

          it "prevents from running the consistency checks twice on the same world concurrently" do
            client_world.invalidate(executor_world.registered_world)
            expected_locks = ["lock world-invalidation:#{executor_world.id}",
                              "unlock world-invalidation:#{executor_world.id}"]
            client_world.coordinator.adapter.lock_log.must_equal(expected_locks)
          end
        end
      end

      describe 'auto execute' do
        it "prevents from running the auto-execution twice" do
          client_world.auto_execute
          expected_locks = ["lock auto-execute", "unlock auto-execute"]
          client_world.coordinator.adapter.lock_log.must_equal(expected_locks)
        end

        it "re-runs the plans that were planned but not executed" do
          triggered = client_world.trigger(Support::DummyExample::Dummy)
          triggered.finished.wait
          executor_world.auto_execute
          plan = wait_for do
            plan = client_world.persistence.load_execution_plan(triggered.id)
            if plan.state == :stopped
              plan
            end
          end
          expected_history = [['start execution', executor_world.id],
                              ['finish execution', executor_world.id]]
          plan.execution_history.map { |h| [h.name, h.world_id] }.must_equal(expected_history)
        end

        it "re-runs the plans that were terminated but not re-executed (because no available executor)" do
          executor_world # mention it to get initialized
          triggered = while_executing_plan { |executor| executor.terminate.wait }
          executor_world_2.auto_execute
          finish_the_plan(triggered)
          plan = wait_for do
            plan = client_world.persistence.load_execution_plan(triggered.id)
            if plan.state == :stopped
              plan
            end
          end
          assert_plan_reexecuted(plan)
        end

        it "doesn't rerun the plans that were paused with error" do
          executor_world # mention it to get initialized
          triggered = client_world.trigger(Support::DummyExample::FailingDummy)
          triggered.finished.wait
          executor_world.auto_execute
          plan = client_world.persistence.load_execution_plan(triggered.id)
          plan.state.must_equal :paused
          expected_history = [['start execution', executor_world.id],
                              ['finish execution', executor_world.id]]
          plan.execution_history.map { |h| [h.name, h.world_id] }.must_equal(expected_history)
        end
      end
    end
  end
end

