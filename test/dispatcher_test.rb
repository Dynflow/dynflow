require_relative 'test_helper'

module Dynflow
  module DispatcherTest
    describe "dispatcher" do

      include TestHelpers

      let(:persistence_adapter) { WorldFactory.persistence_adapter }

      def self.dispatcher_works_with_this_connector
        describe 'connector basics' do
          before do
            # just mention the executor to initialize it
            executor_world
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
              plan   = result.finished.value!
              step   = plan.steps.values.first
              future = client_world.event(plan.id, step.id, 'finish')
              future.wait
              assert future.failed?
            end

            it 'succeeds when executor acts as client' do
              result = client_world.trigger(Support::DummyExample::ComposedAction, :timeout => 3)
              plan = result.finished.value
              assert_equal('finish', plan.actions.first.output[:event])
            end
          end
        end
      end

      def self.supports_dynamic_retry
        before do
          # mention the executors to make sure they are initialized
          @executors = [executor_world, executor_world_2]
        end

        describe 'when some executor is terminated and client is notified about the failure' do
          specify 'client passes the work to another executor' do
            triggered = while_executing_plan { |executor| executor.terminate.wait }
            plan = finish_the_plan(triggered)
            assert_plan_reexecuted(plan)
          end
        end

      end

      def self.supports_ping_pong
        describe 'ping/pong' do
          it 'succeeds when the world is available' do
            ping_response = client_world.ping(executor_world.id, 0.5)
            ping_response.wait
            assert ping_response.success?
          end

          it 'time-outs when the world is not responding' do
            executor_world.terminate.wait
            ping_response = client_world.ping(executor_world.id, 0.5)
            ping_response.wait
            assert ping_response.failed?
          end
        end
      end

      def self.handles_no_executor_available
        it 'fails to finish the future when no executor available' do
          client_world # just to initialize the client world before terminating the executors
          executor_world.terminate.wait
          executor_world_2.terminate.wait
          result = client_world.trigger(Support::DummyExample::Dummy)
          result.finished.wait
          assert result.finished.failed?
          assert_match(/No executor available/, result.finished.reason.message)
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
        supports_ping_pong
        handles_no_executor_available
      end

      describe 'database connector - all in one' do
        let(:connector) { Proc.new { |world| Connectors::Database.new(world, connector_polling_interval(world)) } }
        let(:executor_world) { create_world }
        let(:client_world) { executor_world }

        dispatcher_works_with_this_connector
        supports_ping_pong
      end

      describe 'database connector - multi executor multi client' do
        let(:connector) { Proc.new { |world| Connectors::Database.new(world, connector_polling_interval(world)) } }
        let(:executor_world) { create_world(true) }
        let(:executor_world_2) { create_world(true) }
        let(:client_world) { create_world(false) }
        let(:client_world_2) { create_world(false) }

        dispatcher_works_with_this_connector
        supports_dynamic_retry
        supports_ping_pong
        handles_no_executor_available
      end
    end
  end
end
