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
          world.persistence.delete_delayed_plans({})
        end

        let(:world) { WorldFactory.create_world }
        let(:delayed_plan) do
          delayed_plan = world.delay(::Support::DummyExample::Dummy, { :start_at => @start_at })
          delayed_plan.must_be :scheduled?
          world.persistence.load_delayed_plan(delayed_plan.execution_plan_id)
        end
        let(:history_names) do
          ->(execution_plan) { execution_plan.execution_history.map(&:name) }
        end
        let(:execution_plan) { delayed_plan.execution_plan }

        it 'returns the progress as 0' do
          execution_plan.progress.must_equal 0
        end

        it 'marks the plan as failed when issues in serialied phase' do
          world.persistence.delete_execution_plans({})
          e = proc { world.delay(::Support::DummyExample::DummyCustomDelaySerializer, { :start_at => @start_at }, :fail) }.must_raise RuntimeError
          e.message.must_equal 'Enforced serializer failure'
          plan = world.persistence.find_execution_plans(page: 0, per_page: 1, order_by: :ended_at, desc: true).first
          plan.state.must_equal :stopped
          plan.result.must_equal :error
        end

        it 'delays the action' do
          execution_plan.steps.count.must_equal 1
          delayed_plan.start_at.inspect.must_equal (@start_at).inspect
          history_names.call(execution_plan).must_equal ['delay']
        end

        it 'allows cancelling the delayed plan' do
          execution_plan.state.must_equal :scheduled
          execution_plan.cancellable?.must_equal true
          execution_plan.cancel.each(&:wait)
          execution_plan = world.persistence.load_execution_plan(self.execution_plan.id)
          execution_plan.state.must_equal :stopped
          execution_plan.result.must_equal :error
          assert_nil execution_plan.delay_record
        end

        it 'finds delayed plans' do
          @start_at = Time.now.utc - 100
          delayed_plan
          past_delayed_plans = world.persistence.find_past_delayed_plans(@start_at + 10)
          past_delayed_plans.length.must_equal 1
          past_delayed_plans.first.execution_plan_uuid.must_equal execution_plan.id
        end

        it 'delayed plans can be planned and executed' do
          execution_plan.state.must_equal :scheduled
          delayed_plan.plan
          execution_plan.state.must_equal :planned
          execution_plan.result.must_equal :pending
          assert_planning_success execution_plan
          history_names.call(execution_plan).must_equal ['delay']
          delayed_plan.execute.future.wait
          executed = world.persistence.load_execution_plan(delayed_plan.execution_plan_uuid)
          executed.state.must_equal :stopped
          executed.result.must_equal :success
          executed.execution_history.count.must_equal 3
        end

        it 'expired plans can be failed' do
          delayed_plan.timeout
          execution_plan.state.must_equal :stopped
          execution_plan.result.must_equal :error
          execution_plan.errors.first.message.must_match /could not be started before set time/
          history_names.call(execution_plan).must_equal %W(delay timeout)
        end

      end

      describe 'polling delayed executor' do
        let(:dummy_world) { Dynflow::Testing::DummyWorld.new }
        let(:persistence) { MiniTest::Mock.new }
        let(:options) { { :poll_interval => 15, :time_source => -> { dummy_world.clock.current_time } } }
        let(:delayed_executor) { DelayedExecutors::Polling.new(dummy_world, options) }
        let(:klok) { dummy_world.clock }

        it 'checks for delayed plans in regular intervals' do
          start_time = klok.current_time
          persistence.expect(:find_past_delayed_plans, [], [start_time])
          persistence.expect(:find_past_delayed_plans, [], [start_time + options[:poll_interval]])
          dummy_world.stub :persistence, persistence do
            klok.pending_pings.length.must_equal 0
            delayed_executor.start.wait
            klok.pending_pings.length.must_equal 1
            klok.pending_pings.first.who.ref.must_be_same_as delayed_executor.core
            klok.pending_pings.first.when.must_equal start_time + options[:poll_interval]
            klok.progress
            delayed_executor.terminate.wait
            klok.pending_pings.length.must_equal 1
            klok.pending_pings.first.who.ref.must_be_same_as delayed_executor.core
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
            serializer = serializer_class.new(input)
            serializer.perform_serialization!
            serialized_args = save_and_load.call(serializer.serialized_args)
            serializer = serializer_class.new(nil, serialized_args)
            serializer.perform_deserialization!
            serializer.args
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
