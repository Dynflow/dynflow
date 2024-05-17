# frozen_string_literal: true

require_relative 'test_helper'
require 'multi_json'

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
          _(delayed_plan).must_be :scheduled?
          world.persistence.load_delayed_plan(delayed_plan.execution_plan_id)
        end
        let(:history_names) do
          ->(execution_plan) { execution_plan.execution_history.map(&:name) }
        end
        let(:execution_plan) { delayed_plan.execution_plan }

        describe 'abstract executor' do
          let(:abstract_delayed_executor) { DelayedExecutors::AbstractCore.new(world) }

          it 'handles plan in planning state' do
            delayed_plan.execution_plan.state = :planning
            abstract_delayed_executor.send(:process, [delayed_plan], @start_at)
            _(delayed_plan.execution_plan.state).must_equal :scheduled
          end

          it 'handles plan in running state' do
            delayed_plan.execution_plan.set_state(:running, true)
            abstract_delayed_executor.send(:process, [delayed_plan], @start_at)
            _(delayed_plan.execution_plan.state).must_equal :running
            _(world.persistence.load_delayed_plan(delayed_plan.execution_plan_uuid)).must_be :nil?
          end
        end

        it 'returns the progress as 0' do
          _(execution_plan.progress).must_equal 0
        end

        it 'marks the plan as failed when issues in serialied phase' do
          world.persistence.delete_execution_plans({})
          e = _(proc { world.delay(::Support::DummyExample::DummyCustomDelaySerializer, { :start_at => @start_at }, :fail) }).must_raise RuntimeError
          _(e.message).must_equal 'Enforced serializer failure'
          plan = world.persistence.find_execution_plans(page: 0, per_page: 1, order_by: :ended_at, desc: true).first
          _(plan.state).must_equal :stopped
          _(plan.result).must_equal :error
        end

        it 'delays the action' do
          _(execution_plan.steps.count).must_equal 1
          _(delayed_plan.start_at.to_i).must_equal(@start_at.to_i)
          _(history_names.call(execution_plan)).must_equal ['delay']
        end

        it 'allows cancelling the delayed plan' do
          _(execution_plan.state).must_equal :scheduled
          _(execution_plan.cancellable?).must_equal true
          execution_plan.cancel.each(&:wait)
          execution_plan = world.persistence.load_execution_plan(self.execution_plan.id)
          _(execution_plan.state).must_equal :stopped
          _(execution_plan.result).must_equal :cancelled
          assert_nil execution_plan.delay_record
        end

        it 'finds delayed plans' do
          @start_at = Time.now.utc - 100
          delayed_plan
          past_delayed_plans = world.persistence.find_ready_delayed_plans(@start_at + 10)
          _(past_delayed_plans.length).must_equal 1
          _(past_delayed_plans.first.execution_plan_uuid).must_equal execution_plan.id
        end

        it 'delayed plans can be planned and executed' do
          _(execution_plan.state).must_equal :scheduled
          delayed_plan.plan
          _(execution_plan.state).must_equal :planned
          _(execution_plan.result).must_equal :pending
          assert_planning_success execution_plan
          _(history_names.call(execution_plan)).must_equal ['delay']
          delayed_plan.execute.future.wait
          executed = world.persistence.load_execution_plan(delayed_plan.execution_plan_uuid)
          _(executed.state).must_equal :stopped
          _(executed.result).must_equal :success
          _(executed.execution_history.count).must_equal 3
        end

        it 'expired plans can be failed' do
          delayed_plan.timeout
          _(execution_plan.state).must_equal :stopped
          _(execution_plan.result).must_equal :error
          _(execution_plan.errors.first.message).must_match(/could not be started before set time/)
          _(history_names.call(execution_plan)).must_equal %W(delay timeout)
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
          persistence.expect(:find_ready_delayed_plans, [], [start_time])
          persistence.expect(:find_ready_delayed_plans, [], [start_time + options[:poll_interval]])
          dummy_world.stub :persistence, persistence do
            _(klok.pending_pings.length).must_equal 0
            delayed_executor.start.wait
            _(klok.pending_pings.length).must_equal 1
            _(klok.pending_pings.first.who.ref).must_be_same_as delayed_executor.core
            _(klok.pending_pings.first.when).must_equal start_time + options[:poll_interval]
            klok.progress
            delayed_executor.terminate.wait
            _(klok.pending_pings.length).must_equal 1
            _(klok.pending_pings.first.who.ref).must_be_same_as delayed_executor.core
            _(klok.pending_pings.first.when).must_equal start_time + 2 * options[:poll_interval]
            klok.progress
            _(klok.pending_pings.length).must_equal 0
          end
        end
      end

      describe 'serializers' do
        let(:args) { %w(arg1 arg2) }
        let(:serialized_serializer) { Dynflow::Serializers::Noop.new(nil, args) }
        let(:deserialized_serializer) { Dynflow::Serializers::Noop.new(args, nil) }
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
          _(simulated_use.call(Dynflow::Serializers::Noop, input)).must_equal input
        end

        it 'args! raises if not deserialized' do
          _(proc { serialized_serializer.args! }).must_raise RuntimeError
          deserialized_serializer.args! # Must not raise
        end

        it 'serialized_args! raises if not serialized' do
          _(proc { deserialized_serializer.serialized_args! }).must_raise RuntimeError
          serialized_serializer.serialized_args! # Must not raise
        end

        it 'performs_serialization!' do
          deserialized_serializer.perform_serialization!
          _(deserialized_serializer.serialized_args!).must_equal args
        end

        it 'performs_deserialization!' do
          serialized_serializer.perform_deserialization!
          _(serialized_serializer.args).must_equal args
        end
      end

      describe 'delayed plan' do
        let(:args) { %w(arg1 arg2) }
        let(:serializer) { Dynflow::Serializers::Noop.new(nil, args) }
        let(:delayed_plan) do
          Dynflow::DelayedPlan.new(Dynflow::World.allocate, 'an uuid', nil, nil, serializer, false)
        end

        it "allows access to serializer's args" do
          _(serializer.args).must_be :nil?
          _(delayed_plan.args).must_equal args
          _(serializer.args).must_equal args
        end
      end

      describe 'execution plan chaining' do
        let(:world) do
          WorldFactory.create_world { |config| config.auto_rescue = true }
        end

        before do
          @preexisting = world.persistence.find_ready_delayed_plans(Time.now).map(&:execution_plan_uuid)
        end

        it 'chains two execution plans' do
          plan1 = world.plan(Support::DummyExample::Dummy)
          plan2 = world.chain(plan1.id, Support::DummyExample::Dummy)

          Concurrent::Promises.resolvable_future.tap do |promise|
            world.execute(plan1.id, promise)
          end.wait

          plan1 = world.persistence.load_execution_plan(plan1.id)
          _(plan1.state).must_equal :stopped
          ready = world.persistence.find_ready_delayed_plans(Time.now).reject { |p| @preexisting.include? p.execution_plan_uuid }
          _(ready.count).must_equal 1
          _(ready.first.execution_plan_uuid).must_equal plan2.execution_plan_id
        end

        it 'chains onto multiple execution plans and waits for all to finish' do
          plan1 = world.plan(Support::DummyExample::Dummy)
          plan2 = world.plan(Support::DummyExample::Dummy)
          plan3 = world.chain([plan2.id, plan1.id], Support::DummyExample::Dummy)

          # Execute and complete plan1
          Concurrent::Promises.resolvable_future.tap do |promise|
            world.execute(plan1.id, promise)
          end.wait

          plan1 = world.persistence.load_execution_plan(plan1.id)
          _(plan1.state).must_equal :stopped

          # plan3 should still not be ready because plan2 hasn't finished yet
          ready = world.persistence.find_ready_delayed_plans(Time.now).reject { |p| @preexisting.include? p.execution_plan_uuid }
          _(ready.count).must_equal 0

          # Execute and complete plan2
          Concurrent::Promises.resolvable_future.tap do |promise|
            world.execute(plan2.id, promise)
          end.wait

          plan2 = world.persistence.load_execution_plan(plan2.id)
          _(plan2.state).must_equal :stopped

          # Now plan3 should be ready since both plan1 and plan2 are complete
          ready = world.persistence.find_ready_delayed_plans(Time.now).reject { |p| @preexisting.include? p.execution_plan_uuid }
          _(ready.count).must_equal 1
          _(ready.first.execution_plan_uuid).must_equal plan3.execution_plan_id
        end

        it 'cancels the chained plan if the prerequisite fails' do
          plan1 = world.plan(Support::DummyExample::FailingDummy)
          plan2 = world.chain(plan1.id, Support::DummyExample::Dummy)

          Concurrent::Promises.resolvable_future.tap do |promise|
            world.execute(plan1.id, promise)
          end.wait

          plan1 = world.persistence.load_execution_plan(plan1.id)
          _(plan1.state).must_equal :stopped
          _(plan1.result).must_equal :error

          # plan2 will appear in ready delayed plans
          ready = world.persistence.find_ready_delayed_plans(Time.now).reject { |p| @preexisting.include? p.execution_plan_uuid }
          _(ready.map(&:execution_plan_uuid)).must_equal [plan2.execution_plan_id]

          # Process the delayed plan through the director
          work_item = Dynflow::Director::PlanningWorkItem.new(plan2.execution_plan_id, :default, world.id)
          work_item.world = world
          work_item.execute

          # Now plan2 should be stopped with error due to failed dependency
          plan2 = world.persistence.load_execution_plan(plan2.execution_plan_id)
          _(plan2.state).must_equal :stopped
          _(plan2.result).must_equal :error
          _(plan2.errors.first.message).must_match(/prerequisite execution plans failed/)
          _(plan2.errors.first.message).must_match(/#{plan1.id}/)
        end

        it 'cancels the chained plan if at least one prerequisite fails' do
          plan1 = world.plan(Support::DummyExample::Dummy)
          plan2 = world.plan(Support::DummyExample::FailingDummy)
          plan3 = world.chain([plan1.id, plan2.id], Support::DummyExample::Dummy)

          # Execute and complete plan1 successfully
          Concurrent::Promises.resolvable_future.tap do |promise|
            world.execute(plan1.id, promise)
          end.wait

          plan1 = world.persistence.load_execution_plan(plan1.id)
          _(plan1.state).must_equal :stopped
          _(plan1.result).must_equal :success

          # plan3 should still not be ready because plan2 hasn't finished yet
          ready = world.persistence.find_ready_delayed_plans(Time.now).reject { |p| @preexisting.include? p.execution_plan_uuid }
          _(ready).must_equal []

          # Execute and complete plan2 with failure
          Concurrent::Promises.resolvable_future.tap do |promise|
            world.execute(plan2.id, promise)
          end.wait

          plan2 = world.persistence.load_execution_plan(plan2.id)
          _(plan2.state).must_equal :stopped
          _(plan2.result).must_equal :error

          # plan3 will now appear in ready delayed plans even though one prerequisite failed
          ready = world.persistence.find_ready_delayed_plans(Time.now).reject { |p| @preexisting.include? p.execution_plan_uuid }
          _(ready.map(&:execution_plan_uuid)).must_equal [plan3.execution_plan_id]

          # Process the delayed plan through the director
          work_item = Dynflow::Director::PlanningWorkItem.new(plan3.execution_plan_id, :default, world.id)
          work_item.world = world
          work_item.execute

          # Now plan3 should be stopped with error due to failed dependency
          plan3 = world.persistence.load_execution_plan(plan3.execution_plan_id)
          _(plan3.state).must_equal :stopped
          _(plan3.result).must_equal :error
          _(plan3.errors.first.message).must_match(/prerequisite execution plans failed/)
          _(plan3.errors.first.message).must_match(/#{plan2.id}/)
        end

        it 'chains runs the chained plan if the prerequisite was halted' do
          plan1 = world.plan(Support::DummyExample::Dummy)
          plan2 = world.chain(plan1.id, Support::DummyExample::Dummy)

          world.halt(plan1.id)
          Concurrent::Promises.resolvable_future.tap do |promise|
            world.execute(plan1.id, promise)
          end.wait

          plan1 = world.persistence.load_execution_plan(plan1.id)
          _(plan1.state).must_equal :stopped
          _(plan1.result).must_equal :pending
          ready = world.persistence.find_ready_delayed_plans(Time.now).reject { |p| @preexisting.include? p.execution_plan_uuid }
          _(ready.count).must_equal 1
          _(ready.first.execution_plan_uuid).must_equal plan2.execution_plan_id
        end
      end
    end
  end
end
