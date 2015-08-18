require_relative 'test_helper'
require 'fileutils'

module Dynflow
  module PersistenceTest
    describe 'persistence adapters' do

      let :execution_plans_data do
        [{ id: 'plan1', state: 'paused' },
         { id: 'plan2', state: 'stopped' },
         { id: 'plan3', state: 'paused' },
         { id: 'plan4', state: 'paused' }]
      end

      let :action_data do
        { id: 1, caller_execution_plan_id: nil, caller_action_id: nil }
      end

      let :step_data do
        { id: 1,
          state: 'success',
          started_at: '2015-02-24 10:00',
          ended_at: '2015-02-24 10:01',
          real_time: 1.1,
          execution_time: 0.1,
          action_id: 1,
          progress_done: 1,
          progress_weight: 2.5 }
      end

      def prepare_plans
        execution_plans_data.map do |h|
          h.merge result:    nil, started_at: (Time.now-20).to_s, ended_at: (Time.now-10).to_s,
              real_time: 0.0, execution_time: 0.0
        end.tap do |plans|
          plans.each { |plan| adapter.save_execution_plan(plan[:id], plan) }
        end
      end

      def prepare_action(plan)
        adapter.save_action(plan, action_data[:id], action_data)
      end

      def prepare_step(plan)
        adapter.save_step(plan, step_data[:id], step_data)
      end

      def prepare_plans_with_actions
        prepare_plans.each do |plan|
          prepare_action(plan[:id])
        end
      end

      def prepare_plans_with_steps
        prepare_plans_with_actions.map do |plan|
          prepare_step(plan[:id])
        end
      end

      def self.it_acts_as_persistence_adapter
        before do
          # the tests expect clean field
          adapter.delete_execution_plans({})
        end
        describe '#find_execution_plans' do
          it 'supports pagination' do
            prepare_plans
            if adapter.pagination?
              loaded_plans = adapter.find_execution_plans(page: 0, per_page: 1)
              loaded_plans.map { |h| h[:id] }.must_equal ['plan1']

              loaded_plans = adapter.find_execution_plans(page: 1, per_page: 1)
              loaded_plans.map { |h| h[:id] }.must_equal ['plan2']
            end
          end

          it 'supports ordering' do
            prepare_plans
            if adapter.ordering_by.include?(:state)
              loaded_plans = adapter.find_execution_plans(order_by: 'state')
              loaded_plans.map { |h| h[:id] }.must_equal ['plan1', 'plan3', 'plan2']

              loaded_plans = adapter.find_execution_plans(order_by: 'state', desc: true)
              loaded_plans.map { |h| h[:id] }.must_equal ['plan2', 'plan3', 'plan1']
            end
          end

          it 'supports filtering' do
            prepare_plans
            if adapter.ordering_by.include?(:state)
              loaded_plans = adapter.find_execution_plans(filters: { state: ['paused'] })
              loaded_plans.map { |h| h[:id] }.must_equal ['plan1', 'plan3']

              loaded_plans = adapter.find_execution_plans(filters: { state: ['stopped'] })
              loaded_plans.map { |h| h[:id] }.must_equal ['plan2']

              loaded_plans = adapter.find_execution_plans(filters: { state: [] })
              loaded_plans.map { |h| h[:id] }.must_equal []

              loaded_plans = adapter.find_execution_plans(filters: { state: ['stopped', 'paused'] })
              loaded_plans.map { |h| h[:id] }.must_equal ['plan1', 'plan2', 'plan3']

              loaded_plans = adapter.find_execution_plans(filters: { 'state' => ['stopped', 'paused'] })
              loaded_plans.map { |h| h[:id] }.must_equal ['plan1', 'plan2', 'plan3']
            end
          end
        end

        describe '#load_execution_plan and #save_execution_plan' do
          it 'serializes/deserializes the plan data' do
            -> { adapter.load_execution_plan('plan1') }.must_raise KeyError
            prepare_plans
            adapter.load_execution_plan('plan1')[:id].must_equal 'plan1'
            adapter.load_execution_plan('plan1')['id'].must_equal 'plan1'
            adapter.load_execution_plan('plan1').keys.size.must_equal 7

            adapter.save_execution_plan('plan1', nil)
            -> { adapter.load_execution_plan('plan1') }.must_raise KeyError
          end
        end

        describe '#delete_execution_plans' do
          it 'deletes selected execution plans, including steps and actions' do
            prepare_plans_with_steps
            adapter.delete_execution_plans('uuid' => 'plan1').must_equal 1
            -> { adapter.load_execution_plan('plan1') }.must_raise KeyError
            -> { adapter.load_action('plan1', action_data[:id]) }.must_raise KeyError
            -> { adapter.load_step('plan1', step_data[:id]) }.must_raise KeyError

            # testing that no other plans where affected
            adapter.load_execution_plan('plan2')
            adapter.load_action('plan2', action_data[:id])
            adapter.load_step('plan2', step_data[:id])

            prepare_plans_with_steps
            adapter.delete_execution_plans('state' => 'paused').must_equal 3
            -> { adapter.load_execution_plan('plan1') }.must_raise KeyError
            adapter.load_execution_plan('plan2') # nothing raised
            -> { adapter.load_execution_plan('plan3') }.must_raise KeyError
          end
        end

        describe '#load_action and #save_action' do
          it 'serializes/deserializes the action data' do
            prepare_plans
            action_id = action_data[:id]
            -> { adapter.load_action('plan1', action_id) }.must_raise KeyError

            prepare_action('plan1')
            loaded_action = adapter.load_action('plan1', action_id)
            loaded_action[:id].must_equal action_id
            loaded_action.must_equal(Utils.stringify_keys(action_data))

            adapter.save_action('plan1', action_id, nil)
            -> { adapter.load_action('plan1', action_id) }.must_raise KeyError

            adapter.save_execution_plan('plan1', nil)
          end
        end

        describe '#load_step and #save_step' do
          it 'serializes/deserializes the step data' do
            prepare_plans_with_actions
            step_id = step_data[:id]
            prepare_step('plan1')
            loaded_step = adapter.load_step('plan1', step_id)
            loaded_step[:id].must_equal step_id
            loaded_step.must_equal(Utils.stringify_keys(step_data))
          end
        end

        describe '#find_past_delayed_plans' do
          it 'finds plans with start_before in past' do
            start_time = Time.now
            prepare_plans
            fmt =->(time) { time.strftime('%Y-%m-%d %H:%M:%S') }
            adapter.save_delayed_plan('plan1', :execution_plan_uuid => 'plan1', :start_at => fmt.call(start_time + 60), :start_before => fmt.call(start_time - 60))
            adapter.save_delayed_plan('plan2', :execution_plan_uuid => 'plan2', :start_at => fmt.call(start_time - 60))
            adapter.save_delayed_plan('plan3', :execution_plan_uuid => 'plan3', :start_at => fmt.call(start_time + 60))
            adapter.save_delayed_plan('plan4', :execution_plan_uuid => 'plan4', :start_at => fmt.call(start_time - 60), :start_before => fmt.call(start_time - 60))
            plans = adapter.find_past_delayed_plans(start_time)
            plans.length.must_equal 3
            plans.map { |plan| plan[:execution_plan_uuid] }.must_equal %w(plan2 plan4 plan1)
          end
        end
      end

      describe Dynflow::PersistenceAdapters::Sequel do
        let(:adapter) { Dynflow::PersistenceAdapters::Sequel.new 'sqlite:/' }

        it_acts_as_persistence_adapter

        it 'allows inspecting the persisted content' do
          plans = prepare_plans

          plans.each do |original|
            stored = adapter.to_hash.fetch(:execution_plans).find { |ep| ep[:uuid].strip == original[:id] }
            stored.each { |k, v| stored[k] = v.to_s if v.is_a? Time }
            adapter.class::META_DATA.fetch(:execution_plan).each do |name|
              stored.fetch(name.to_sym).must_equal original.fetch(name.to_sym)
            end
          end
        end

        it "supports connector's needs for exchaning envelopes" do
          client_world_id   = '5678'
          executor_world_id = '1234'
          envelope_hash = ->(envelope) { Dynflow::Utils.indifferent_hash(Dynflow.serializer.dump(envelope)) }
          executor_envelope = envelope_hash.call(Dispatcher::Envelope[123, client_world_id, executor_world_id, Dispatcher::Execution['111']])
          client_envelope   = envelope_hash.call(Dispatcher::Envelope[123, executor_world_id, client_world_id, Dispatcher::Accepted])
          envelopes         = [client_envelope, executor_envelope]

          envelopes.each { |e| adapter.push_envelope(e) }

          assert_equal [executor_envelope], adapter.pull_envelopes(executor_world_id)
          assert_equal [client_envelope],   adapter.pull_envelopes(client_world_id)
          assert_equal [], adapter.pull_envelopes(client_world_id)
          assert_equal [], adapter.pull_envelopes(executor_world_id)
        end

      end
    end
  end
end
