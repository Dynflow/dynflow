require_relative 'test_helper'

module Dynflow
  module FutureExecutionTest
    describe 'Future Execution' do
      include PlanAssertions
      include Dynflow::Testing::Assertions
      include Dynflow::Testing::Factories

      describe 'action scheduling' do

        before do
          @start_at = Time.now.utc + 180
          world.persistence.delete_scheduled_plans(:execution_plan_uuid => [])
        end

        let(:world) { WorldFactory.create_world }
        let(:plan) do
          scheduled = world.schedule(::Support::DummyExample::Dummy, { :start_at => @start_at })
          scheduled.must_be :scheduled?
          world.persistence.load_scheduled_plan(scheduled.execution_plan_id)
        end
        let(:history_names) do
          ->(execution_plan) { execution_plan.execution_history.map(&:name) }
        end
        let(:execution_plan) { plan.execution_plan }

        it 'returns the progress as 0' do
          execution_plan.progress.must_equal 0
        end

        it 'schedules the action' do
          execution_plan.steps.count.must_equal 1
          plan.start_at.inspect.must_equal (@start_at).inspect
          history_names.call(execution_plan).must_equal ['schedule']
        end

        it 'finds scheduled plans' do
          @start_at = Time.now.utc - 100
          plan
          past_scheduled_plans = world.persistence.find_past_scheduled_plans(@start_at + 10)
          past_scheduled_plans.length.must_equal 1
          past_scheduled_plans.first.execution_plan_uuid.must_equal execution_plan.id
        end

        it 'scheduled plans can be planned and executed' do
          execution_plan.state.must_equal :scheduled
          plan.plan
          execution_plan.state.must_equal :planned
          execution_plan.result.must_equal :pending
          assert_planning_success execution_plan
          history_names.call(execution_plan).must_equal ['schedule']
          executed = plan.execute
          executed.wait
          executed.value.state.must_equal :stopped
          executed.value.result.must_equal :success
          executed.value.execution_history.count.must_equal 3
        end

        it 'expired plans can be failed' do
          plan.timeout
          execution_plan.state.must_equal :stopped
          execution_plan.result.must_equal :error
          execution_plan.errors.first.message.must_match /could not be started before set time/
          history_names.call(execution_plan).must_equal %W(schedule timeout)
        end

      end

      describe 'polling scheduler' do
        let(:dummy_world) { Dynflow::Testing::DummyWorld.new }
        let(:persistence) { MiniTest::Mock.new }
        let(:options) { { :poll_interval => 15, :time_source => -> { dummy_world.clock.current_time } } }
        let(:scheduler) { Schedulers::Polling.new(dummy_world, options) }
        let(:klok) { dummy_world.clock }

        it 'checks for scheduled plans in regular intervals' do
          start_time = klok.current_time
          persistence.expect(:find_past_scheduled_plans, [], [start_time])
          persistence.expect(:find_past_scheduled_plans, [], [start_time + options[:poll_interval]])
          dummy_world.stub :persistence, persistence do
            klok.pending_pings.length.must_equal 0
            scheduler.start.wait
            klok.pending_pings.length.must_equal 1
            klok.pending_pings.first.who.ref.must_be_same_as scheduler.core
            klok.pending_pings.first.when.must_equal start_time + options[:poll_interval]
            klok.progress
            scheduler.terminate.wait
            klok.pending_pings.length.must_equal 1
            klok.pending_pings.first.who.ref.must_be_same_as scheduler.core
            klok.pending_pings.first.when.must_equal start_time + 2 * options[:poll_interval]
            klok.progress
            klok.pending_pings.length.must_equal 0
          end
        end
      end

      describe 'serializers' do
        let(:save_and_load) do
          ->(thing) { MultiJson.load(MultiJson.dump(thing)) }
        end
        let(:simulated_use) do
          lambda do |serializer_class, input|
            serializer = serializer_class.new
            serializer.deserialize(save_and_load.call(serializer.serialize *input))
          end
        end

        it 'noop serializer [de]serializes correctly for simple types' do
          input = [1, 2.0, 'three', ['four-1', 'four-2'], { 'five' => 5 }]
          simulated_use.call(Dynflow::Serializers::Noop, input).must_equal input
        end
      end
    end
  end
end
