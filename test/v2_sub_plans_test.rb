# frozen_string_literal: true
require_relative 'test_helper'
require 'mocha/minitest'

module Dynflow
  module V2SubPlansTest
    describe 'V2 sub-plans' do
      include PlanAssertions
      include Dynflow::Testing::Assertions
      include Dynflow::Testing::Factories
      include TestHelpers

      let(:world) { WorldFactory.create_world }

      class ChildAction < ::Dynflow::Action
        def run
        end
      end

      class ParentAction < ::Dynflow::Action
        include Dynflow::Action::V2::WithSubPlans

        def plan(count, concurrency_level = nil)
          limit_concurrency_level!(concurrency_level) if concurrency_level
          plan_self :count => count
        end

        def create_sub_plans
          output[:batch_count] ||= 0
          output[:batch_count] += 1
          current_batch.map { |i| trigger(ChildAction) }
        end

        def batch(from, size)
          (1..total_count).to_a.slice(from, size)
        end

        def batch_size
          5
        end

        def total_count
          input[:count]
        end
      end

      describe 'normal operation' do
        it 'spawns all sub-plans in one go with high-enough batch size and polls until they are done' do
          action = create_and_plan_action ParentAction, 3
          action.world.expects(:trigger).times(3)
          action = run_action action
          _(action.output['total_count']).must_equal 3
          _(action.output['planned_count']).must_equal 3
          _(action.output['pending_count']).must_equal 3

          ping = action.world.clock.pending_pings.first
          _(ping.what.value.event).must_equal Dynflow::Action::V2::WithSubPlans::Ping
          _(ping.when).must_be_within_delta(Time.now + action.polling_interval, 1)
          persistence = mock()
          persistence.stubs(:find_execution_plan_counts).returns(0)
          action.world.stubs(:persistence).returns(persistence)

          action.world.clock.progress
          action.world.executor.progress
          ping = action.world.clock.pending_pings.first
          _(ping.what.value.event).must_equal Dynflow::Action::V2::WithSubPlans::Ping
          _(ping.when).must_be_within_delta(Time.now + action.polling_interval * 2, 1)

          persistence = mock()
          persistence.stubs(:find_execution_plan_counts).returns(0).then.returns(3)
          action.world.stubs(:persistence).returns(persistence)
          action.world.clock.progress
          action.world.executor.progress

          _(action.state).must_equal :success
          _(action.done?).must_equal true
        end

        it 'spawns sub-plans in multiple batches and polls until they are done' do
          action = create_and_plan_action ParentAction, 7
          action.world.expects(:trigger).times(5)
          action = run_action action
          _(action.output['total_count']).must_equal 7
          _(action.output['planned_count']).must_equal 5
          _(action.output['pending_count']).must_equal 5

          _(action.world.clock.pending_pings).must_be :empty?
          _, _, event, * = action.world.executor.events_to_process.first
          _(event).must_equal Dynflow::Action::V2::WithSubPlans::Ping
          persistence = mock()
          # Simulate 3 finished
          persistence.stubs(:find_execution_plan_counts).returns(0).then.returns(3)
          action.world.stubs(:persistence).returns(persistence)

          action.world.expects(:trigger).times(2)
          action.world.executor.progress

          ping = action.world.clock.pending_pings.first
          _(ping.what.value.event).must_equal Dynflow::Action::V2::WithSubPlans::Ping
          _(ping.when).must_be_within_delta(Time.now + action.polling_interval, 1)

          persistence.stubs(:find_execution_plan_counts).returns(0).then.returns(7)
          action.world.stubs(:persistence).returns(persistence)
          action.world.clock.progress
          action.world.executor.progress

          _(action.state).must_equal :success
          _(action.done?).must_equal true
        end
      end

      describe 'with concurrency control' do
        include Dynflow::Testing

        it 'allows storage and retrieval' do
          action = create_and_plan_action ParentAction, 0
          action = run_action action
          _(action.concurrency_limit).must_be_nil
          _(action.concurrency_limit_capacity).must_be_nil

          action = create_and_plan_action ParentAction, 0, 1
          action = run_action action

          _(action.input['dynflow']['concurrency_limit']).must_equal 1
          _(action.concurrency_limit).must_equal 1
          _(action.concurrency_limit_capacity).must_equal 1
        end

        it 'reduces the batch size to fit within the concurrency limit' do
          action = create_and_plan_action ParentAction, 5, 2

          # Plan first 2 sub-plans
          action.world.expects(:trigger).times(2)

          action = run_action action
          _(action.output['total_count']).must_equal 5
          _(action.output['planned_count']).must_equal 2
          _(action.output['pending_count']).must_equal 2
          _(action.concurrency_limit_capacity).must_equal 0
          _(action.output['batch_count']).must_equal 1

          ping = action.world.clock.pending_pings.first
          _(ping.what.value.event).must_equal Dynflow::Action::V2::WithSubPlans::Ping
          _(ping.when).must_be_within_delta(Time.now + action.polling_interval, 1)
          persistence = mock()
          # Simulate 1 sub-plan finished
          persistence.stubs(:find_execution_plan_counts).returns(0).then.returns(1)
          action.world.stubs(:persistence).returns(persistence)

          # Only 1 sub-plans fits into the capacity
          action.world.expects(:trigger).times(1)
          action.world.clock.progress
          action.world.executor.progress

          _(action.output['planned_count']).must_equal 3

          persistence = mock()
          persistence.stubs(:find_execution_plan_counts).returns(0).then.returns(2)
          action.world.stubs(:persistence).returns(persistence)
          action.world.expects(:trigger).times(1)
          action.world.clock.progress
          action.world.executor.progress

          _(action.output['planned_count']).must_equal 4

          persistence = mock()
          persistence.stubs(:find_execution_plan_counts).returns(0).then.returns(4)
          action.world.stubs(:persistence).returns(persistence)
          action.world.expects(:trigger).times(1)
          action.world.clock.progress
          action.world.executor.progress

          _(action.output['planned_count']).must_equal 5
          _(action.concurrency_limit_capacity).must_equal 1

          persistence = mock()
          persistence.stubs(:find_execution_plan_counts).returns(0).then.returns(5)
          action.world.stubs(:persistence).returns(persistence)
          action.world.expects(:trigger).never
          action.world.clock.progress
          action.world.executor.progress
          _(action.state).must_equal :success
          _(action.done?).must_equal true
          _(action.concurrency_limit_capacity).must_equal 2
        end
      end
    end
  end
end
