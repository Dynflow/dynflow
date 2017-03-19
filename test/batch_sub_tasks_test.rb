require_relative 'test_helper'

module Dynflow
  module BatchSubTaskTest
    describe 'Batch sub-tasks' do
      include PlanAssertions
      include Dynflow::Testing::Assertions
      include Dynflow::Testing::Factories
      include TestHelpers

      class FailureSimulator
        def self.should_fail?
          @should_fail
        end

        def self.should_fail!
          @should_fail = true
        end

        def self.wont_fail!
          @should_fail = false
        end
      end

      let(:world) { WorldFactory.create_world }

      class ChildAction < ::Dynflow::Action
        def plan(should_fail = false)
          raise "Simulated failure" if FailureSimulator.should_fail?
          plan_self
        end

        def run
          output[:run] = true
        end
      end

      class ParentAction < ::Dynflow::Action
        include Dynflow::Action::WithSubPlans
        include Dynflow::Action::WithBulkSubPlans

        def plan(count, concurrency_level = nil, time_span = nil)
          limit_concurrency_level(concurrency_level) unless concurrency_level.nil?
          distribute_over_time(time_span, count) unless time_span.nil?
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

      it 'starts tasks in batches' do
        FailureSimulator.wont_fail!
        plan = world.plan(ParentAction, 20)
        future = world.execute plan.id
        wait_for { future.completed? }
        action = plan.entry_action

        action.output[:batch_count].must_equal action.total_count / action.batch_size
      end

      it 'can resume tasks' do
        FailureSimulator.should_fail!
        plan = world.plan(ParentAction, 20)
        future = world.execute plan.id
        wait_for { future.completed? }
        action = plan.entry_action
        action.output[:batch_count].must_equal 1
        future.value.state.must_equal :paused

        FailureSimulator.wont_fail!
        future = world.execute plan.id
        wait_for { future.completed? }
        action = future.value.entry_action
        future.value.state.must_equal :stopped
        action.output[:batch_count].must_equal (action.total_count / action.batch_size) + 1
        action.output[:total_count].must_equal action.total_count
        action.output[:success_count].must_equal action.total_count
      end

    end
  end
end
