# -*- coding: utf-8 -*-
require_relative 'test_helper'
require 'ostruct'

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
      let(:shared_connector) { Connectors::Direct.new }
      let(:connector) { Proc.new { |world| shared_connector.start_listening(world); shared_connector } }
      let(:executor_world) { create_world(true) { |config| config.auto_validity_check = true } }
      let(:executor_world_2) { create_world(true) { |config| config.auto_validity_check = true } }
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

          it "handles missing execution plans" do
            lock = Coordinator::ExecutionLock.new(executor_world, "missing", nil, nil)
            executor_world.coordinator.acquire(lock)
            client_world.invalidate(executor_world.registered_world)
            expected_locks = ["lock world-invalidation:#{executor_world.id}",
                              "unlock execution-plan:missing",
                              "unlock world-invalidation:#{executor_world.id}"]
            client_world.coordinator.adapter.lock_log.must_equal(expected_locks)
          end
        end
      end

      describe 'auto execute' do

        before do
          client_world.persistence.find_execution_plans({}).each do |plan|
            # make sure we don't handle plans from previous tests
            # TODO: delete the plans instead, once we have
            # https://github.com/Dynflow/dynflow/pull/141 merged
            plan.set_state(:stopped, true)
            plan.save
          end
        end

        it "prevents from running the auto-execution twice" do
          client_world.auto_execute
          expected_locks = ["lock auto-execute", "unlock auto-execute"]
          client_world.coordinator.adapter.lock_log.must_equal(expected_locks)
          lock = Coordinator::AutoExecuteLock.new(client_world)
          client_world.coordinator.acquire(lock)
          client_world.auto_execute.must_equal []
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
          retries = executor_world.auto_execute
          retries.each(&:wait)
          plan = client_world.persistence.load_execution_plan(triggered.id)
          plan.state.must_equal :paused
          expected_history = [['start execution', executor_world.id],
                              ['finish execution', executor_world.id]]
          plan.execution_history.map { |h| [h.name, h.world_id] }.must_equal(expected_history)
        end
      end

      describe '#worlds_validity_check' do
        describe 'the auto_validity_check is enabled' do
          let :invalid_world do
            Coordinator::ClientWorld.new(OpenStruct.new(id: '123', meta: {}))
          end

          let :invalid_world_2 do
            Coordinator::ClientWorld.new(OpenStruct.new(id: '456', meta: {}))
          end

          let :client_world do
            create_world(false)
          end

          let :world_with_auto_validity_check do
            create_world do |config|
              config.auto_validity_check = true
              config.validity_check_timeout = 0.2
            end
          end

          it 'performs the validity check on world creation if auto_validity_check enabled' do
            client_world.coordinator.register_world(invalid_world)
            client_world.coordinator.find_worlds(false, id: invalid_world.id).wont_be_empty
            world_with_auto_validity_check
            client_world.coordinator.find_worlds(false, id: invalid_world.id).must_be_empty
          end

          it 'by default, the auto_validity_check is enabled only for executor words' do
            client_world_config = Config::ForWorld.new(Config.new.tap { |c| c.executor = false }, create_world )
            client_world_config.auto_validity_check.must_equal false

            executor_world_config = Config::ForWorld.new(Config.new.tap { |c| c.executor = lambda { |w, _| Executors::Parallel.new(w) } }, create_world )
            executor_world_config.auto_validity_check.must_equal true
          end

          it 'reports the validation status' do
            client_world.coordinator.register_world(invalid_world)
            results = client_world.worlds_validity_check
            client_world.coordinator.find_worlds(false, id: invalid_world.id).must_be_empty

            results[invalid_world.id].must_equal :invalidated

            results[client_world.id].must_equal :valid
          end

          it 'allows checking only, without actual invalidation' do
            client_world.coordinator.register_world(invalid_world)
            results = client_world.worlds_validity_check(false)
            client_world.coordinator.find_worlds(false, id: invalid_world.id).wont_be_empty

            results[invalid_world.id].must_equal :invalid
          end

          it 'allows to filter the worlds to run the check on' do
            client_world.coordinator.register_world(invalid_world)
            client_world.coordinator.register_world(invalid_world_2)
            client_world.coordinator.find_worlds(false, id: [invalid_world.id, invalid_world_2.id]).size.must_equal 2

            results = client_world.worlds_validity_check(true, :id => invalid_world.id)
            results.must_equal(invalid_world.id =>  :invalidated)
            client_world.coordinator.find_worlds(false, id: [invalid_world.id, invalid_world_2.id]).size.must_equal 1
          end
        end
      end

      describe '#coordinator_validity_check' do
        describe 'the auto_validity_check is enabled' do
          let :world_with_auto_validity_check do
            create_world do |config|
              config.auto_validity_check = true
            end
          end

          let(:invalid_lock) { Coordinator::DelayedExecutorLock.new(OpenStruct.new(:id => 'invalid-world-id')) }
          let(:valid_lock) { Coordinator::AutoExecuteLock.new(client_world) }

          def current_locks
            client_world.coordinator.find_locks(id: [valid_lock.id, invalid_lock.id])
          end

          before do
            client_world.coordinator.acquire(valid_lock)
            client_world.coordinator.acquire(invalid_lock)
            current_locks.must_include(valid_lock)
            current_locks.must_include(invalid_lock)
          end

          it 'performs the validity check on world creation if auto_validity_check enabled' do
            world_with_auto_validity_check
            current_locks.must_include(valid_lock)
            current_locks.wont_include(invalid_lock)
          end

          it 'performs the validity check on world creation if auto_validity_check enabled' do
            invalid_locks = client_world.locks_validity_check
            current_locks.must_include(valid_lock)
            current_locks.wont_include(invalid_lock)
            invalid_locks.must_include(invalid_lock)
            invalid_locks.wont_include(valid_lock)
          end
        end
      end
    end
  end
end

