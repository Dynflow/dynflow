require_relative 'test_helper'

module Dynflow
  module DispatcherTest
    describe "dispatcher" do

      let(:persistence_adapter) { WorldInstance.persistence_adapter }

      def create_world(with_executor = true)
        WorldInstance.create_world do |config|
          config.connector = connector
          config.persistence_adapter = persistence_adapter
          unless with_executor
            config.executor = false
          end
        end
      end

      def self.dispatcher_works_with_this_connector
        describe 'connector basics' do
          before do
            @executors = [executor_world]
          end

          describe 'execution passing' do
            it 'succeeds when expected' do
              result = client_world.trigger(Support::DummyExample::Dummy)
              assert_equal :success, result.finished.value.result
            end
          end

          describe 'event passing' do
            it 'succeeds when expected' do
              result = client_world.trigger(Support::DummyExample::EventedAction, :timeout => 3)
              step = wait_for do
                client_world.persistence.load_execution_plan(result.id).
                    steps_in_state(:suspended).first
              end
              client_world.event(step.execution_plan_id, step.id, 'finish')
              plan = result.finished.value
              assert_equal('finish', plan.actions.first.output[:event])
            end

            it 'fails the future when the step is not accepting events' do
              result = client_world.trigger(Support::CodeWorkflowExample::Dummy, { :text => "dummy" })
              plan   = result.finished.value
              step   = plan.steps.values.first
              future = client_world.event(plan.id, step.id, 'finish').wait
              assert future.rejected?
            end

            it 'succeeds when executor acts as client' do
              result = client_world.trigger(Support::DummyExample::ComposedAction, :timeout => 3)
              plan = result.finished.value
              assert_equal('finish', plan.actions.first.output[:event])
            end
          end
        end

        def wait_for
          30.times do
            ret = yield
            return ret if ret
            sleep 0.3
          end
          return nil
        end
      end

      def self.supports_dynamic_retry
        before do
          # mention the executors to make sure they are initialized
          @executors = [executor_world, executor_world_2]
        end

        describe 'when some executor is terminated and client is notified about the failure' do
          specify 'client passes the work to another executor' do
            triggered = while_executing { |executor| executor.terminate.wait }
            plan = finish_the_plan(triggered)
            assert_plan_reexecuted(plan)
          end
        end

        def while_executing
          triggered = client_world.trigger(Support::DummyExample::EventedAction)
          executor_info = wait_for do
            if client_world.persistence.load_execution_plan(triggered.id).state == :running
              client_world.persistence.find_executor_for_plan(triggered.id)
            end
          end
          executor = @executors.find { |e| e.id == executor_info.id }
          yield executor
          return triggered
        end

        def finish_the_plan(triggered)
          wait_for do
            client_world.persistence.load_execution_plan(triggered.id).state == :running
          end
          client_world.event(triggered.id, 2, 'finish')
          return triggered.finished.value
        end

        def assert_plan_reexecuted(plan)
          registered_worlds = client_world.persistence.find_worlds({})
          terminated_executor = @executors.find { |e| registered_worlds.all? { |w| w.id != e.id } }
          running_executor = @executors.find { |e| registered_worlds.any? { |w| w.id == e.id } }
          assert_equal :stopped, plan.state
          assert_equal :success, plan.result
          assert_equal plan.execution_history.map { |h| [h.name, h.world_id] },
              [['start execution', terminated_executor.id],
               ['terminate execution', terminated_executor.id],
               ['start execution', running_executor.id],
               ['finish execution', running_executor.id]]
        end
      end

      def self.supports_world_invalidation

        describe 'world invalidation' do
          it 'removes the world from the register' do
            client_world.invalidate(executor_world.registered_world)
            worlds = client_world.persistence.find_worlds({})
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
              assert_equal :paused, plan.state
              assert_equal :pending, plan.result
              assert_equal plan.execution_history.map { |h| [h.name, h.world_id] },
                  [['start execution', executor_world.id],
                   ['terminate execution', executor_world.id]]
            end
          end

          def with_invalidation_while_executing(finish)
            triggered = while_executing do |executor|
              client_world.invalidate(executor.registered_world)
            end
            plan = if finish
                     finish_the_plan(triggered)
                   else
                     # TODO: send response to the client to resolve the future
                     # plan = triggered.finished
                     client_world.persistence.load_execution_plan(triggered.id)
                   end
            yield plan
          ensure
            # just to workaround state transition checks due to our simulation
            # of second world being inactive
            plan.set_state(:running, true)
            plan.save
          end
        end
      end

      def self.supports_ping_pong
        describe 'ping/pong' do
          it 'succeeds when the world is available' do
            ping_response = client_world.ping(executor_world.id, 0.1).wait
            assert ping_response.fulfilled?
          end

          it 'time-outs when the world is not responding' do
            executor_world.terminate.wait
            ping_response = client_world.ping(executor_world.id, 0.1).wait
            assert ping_response.rejected?
          end
        end
      end

      describe 'direct connector - all in one' do
        let(:connector) { Proc.new { |world| Connectors::Direct.new(world) } }
        let(:executor_world) { create_world }
        let(:client_world) { executor_world }

        dispatcher_works_with_this_connector
        supports_ping_pong
      end

      describe 'direct connector - multi executor multi client' do
        let(:shared_connector) { Connectors::Direct.new() }
        let(:connector) { Proc.new { |world| shared_connector.start_listening(world); shared_connector } }
        let(:executor_world) { create_world(true) }
        let(:executor_world_2) { create_world(true) }
        let(:client_world) { create_world(false) }
        let(:client_world_2) { create_world(false) }

        dispatcher_works_with_this_connector
        supports_dynamic_retry
        supports_world_invalidation
        supports_ping_pong
      end

      describe 'database connector - all in one' do
        let(:connector) { Proc.new { |world| Connectors::Database.new(world, 0.005) } }
        let(:executor_world) { create_world }
        let(:client_world) { executor_world }

        dispatcher_works_with_this_connector
        supports_ping_pong
      end

      describe 'database connector - multi executor multi client' do
        let(:connector) { Proc.new { |world| Connectors::Database.new(world, 0.005) } }
        let(:executor_world) { create_world(true) }
        let(:executor_world_2) { create_world(true) }
        let(:client_world) { create_world(false) }
        let(:client_world_2) { create_world(false) }

        dispatcher_works_with_this_connector
        supports_dynamic_retry
        supports_world_invalidation
        supports_ping_pong
      end
    end
  end
end
