require_relative 'test_helper'

module Dynflow
  module ConcurrencyControlTest
    describe 'Concurrency Control' do
      include PlanAssertions
      include Dynflow::Testing::Assertions
      include Dynflow::Testing::Factories
      include TestHelpers

      class FailureSimulator
        def self.should_fail?
          @should_fail || false
        end

        def self.will_fail!
          @should_fail = true
        end

        def self.wont_fail!
          @should_fail = false
        end

        def self.will_sleep!
          @should_sleep = true
        end

        def self.wont_sleep!
          @should_sleep = false
        end

        def self.should_sleep?
          @should_sleep
        end
      end

      before do
        FailureSimulator.wont_fail!
        FailureSimulator.wont_sleep!
      end

      after do
        klok.clear
      end

      class ChildAction < ::Dynflow::Action
        def plan(should_sleep = false)
          raise "Simulated failure" if FailureSimulator.should_fail?
          plan_self :should_sleep => should_sleep
        end

        def run(event = nil)
          unless output[:slept]
            output[:slept] = true
            puts "SLEEPING" if input[:should_sleep]
            suspend { |suspended| world.clock.ping(suspended, 100, [:run]) } if input[:should_sleep]
          end
        end
      end

      class ParentAction < ::Dynflow::Action
        include Dynflow::Action::WithSubPlans

        def plan(count, concurrency_level = nil, time_span = nil, should_sleep = nil)
          limit_concurrency_level(concurrency_level) unless concurrency_level.nil?
          distribute_over_time(time_span) unless time_span.nil?
          plan_self :count => count, :should_sleep => should_sleep
        end

        def create_sub_plans
          input[:count].times.map { |i| trigger(::Dynflow::ConcurrencyControlTest::ChildAction, input[:should_sleep]) }
        end
      end

      let(:klok) { Dynflow::Testing::ManagedClock.new }
      let(:world) do
        WorldFactory.create_world do |config|
          config.throttle_limiter = proc { |world| LoggingThrottleLimiter.new world }
        end
      end

      def check_step(plan, total, finished)
        world.throttle_limiter.observe(plan.id).length.must_equal (total - finished)
        plan.sub_plans.select { |sub| planned? sub }.count.must_equal (total - finished)
        plan.sub_plans.select { |sub| successful? sub }.count.must_equal finished
      end

      def planned?(plan)
        plan.state == :planned && plan.result == :pending
      end

      def successful?(plan)
        plan.state == :stopped && plan.result == :success
      end

      class LoggingThrottleLimiter < Dynflow::ThrottleLimiter

        class LoggingCore < Dynflow::ThrottleLimiter::Core

          attr_reader :running

          def initialize(*args)
            @running = [0]
            super *args
          end

          def release(*args)
            # Discard semaphores without tickets, find the one with least tickets from the rest
            if @semaphores.key? args.first
              tickets = @semaphores[args.first].children.values.map { |sem| sem.tickets }.compact.min
              # Add running count to the log
              @running << (tickets - @semaphores[args.first].free) unless tickets.nil?
            end
            super(*args)
          end
        end

        def core_class
          LoggingThrottleLimiter::LoggingCore
        end
      end

      it 'can be disabled' do
        total = 10
        plan = world.plan(ParentAction, 10)
        future = world.execute plan.id
        wait_for { future.completed? }
        plan.sub_plans.all? { |sub| successful? sub }
        world.throttle_limiter.core.ask!(:running).must_equal [0]
      end

      it 'limits by concurrency level' do
        total = 10
        level = 4
        plan = world.plan(ParentAction, total, level)
        future = world.execute plan.id
        wait_for { future.completed? }
        world.throttle_limiter.core.ask!(:running).max.must_be :<=, level
      end

      it 'allows to cancel' do
        total = 5
        world.stub :clock, klok do
          plan = world.plan(ParentAction, total, 0)
          triggered = world.execute(plan.id)
          wait_for { plan.sub_plans.count == total }
          world.event(plan.id, plan.steps.values.last.id, ::Dynflow::Action::Cancellable::Cancel)
          wait_for { triggered.completed? }
          plan.entry_action.output[:failed_count].must_equal total
          world.throttle_limiter.core.ask!(:running).max.must_be :<=, 0
        end
      end

      it 'calculates time interval correctly' do
        world.stub :clock, klok do
          total = 10
          get_interval = ->(plan) { plan.entry_action.input[:concurrency_control][:time][:meta][:interval] }

          plan = world.plan(ParentAction, total, 1, 10)
          future = world.execute(plan.id)
          wait_for { plan.sub_plans.count == total }
          wait_for { klok.progress; plan.sub_plans.all? { |sub| successful? sub } }
          # 10 tasks over 10 seconds, one task at a time, 1 task every second
          get_interval.call(plan).must_equal 1.0

          plan = world.plan(ParentAction, total, 4, 10)
          world.execute(plan.id)
          wait_for { plan.sub_plans.count == total }
          wait_for { klok.progress; plan.sub_plans.all? { |sub| successful? sub } }
          # 10 tasks over 10 seconds, four tasks at a time, 1 task every 0.25 second
          get_interval.call(plan).must_equal 0.25

          plan = world.plan(ParentAction, total, nil, 10)
          world.execute(plan.id)
          wait_for { plan.sub_plans.count == total }
          wait_for { klok.progress; plan.sub_plans.all? { |sub| successful? sub } }
          # 1o tasks over 10 seconds, one task at a time (default), 1 task every second
          get_interval.call(plan).must_equal 1.0
        end
      end

      it 'uses the throttle limiter to handle the plans' do
        world.stub :clock, klok do
          time_span = 10.0
          total = 10
          level = 2
          plan = world.plan(ParentAction, total, level, time_span)
          start_time = klok.current_time
          world.execute(plan.id)
          wait_for { plan.sub_plans.count == total }
          wait_for { plan.sub_plans.select { |sub| successful? sub }.count == level }
          finished = 2
          check_step(plan, total, finished)
          world.throttle_limiter.observe(plan.id).dup.each do |triggered|
            triggered.future.tap do |future|
              klok.progress
              wait_for { future.completed? }
            end
            finished += 1
            check_step(plan, total, finished)
          end
          end_time = klok.current_time
          (end_time - start_time).must_equal 4
          world.throttle_limiter.observe(plan.id).must_equal []
          world.throttle_limiter.core.ask!(:running).max.must_be :<=, level
        end
      end

      it 'fails tasks which failed to plan immediately' do
        FailureSimulator.will_fail!
        total = 5
        level = 1
        time_span = 10
        plan = world.plan(ParentAction, total, level, time_span)
        future = world.execute(plan.id)
        wait_for { future.completed? }
        plan.sub_plans.all? { |sub| sub.result == :error }.must_equal true
      end

      it 'cancels tasks which could not be started within the time window' do
        world.stub :clock, klok do
          time_span = 10.0
          level = 1
          total = 10
          plan = world.plan(ParentAction, total, level, time_span, true)
          future = world.execute(plan.id)
          wait_for { plan.sub_plans.count == total && plan.sub_plans.all? { |sub| sub.result == :pending } }
          planned, running = plan.sub_plans.partition { |sub| planned? sub }
          planned.count.must_equal total - level
          running.count.must_equal level
          world.throttle_limiter.observe(plan.id).length.must_equal (total - 1)
          4.times { klok.progress }
          wait_for { future.completed? }
          finished, stopped = plan.sub_plans.partition { |sub| successful? sub }
          finished.count.must_equal level
          stopped.count.must_equal (total - level)
        end
      end
    end
  end
end
