require_relative 'test_helper'
require 'tmpdir'

module Dynflow
  module PersistenceTest
    describe 'persistence adapters' do

      let :execution_plans_data do
        [{ id: 'plan1', :label => 'test1', root_plan_step_id: 1, class: 'Dynflow::ExecutionPlan', state: 'paused' },
         { id: 'plan2', :label => 'test2', root_plan_step_id: 1, class: 'Dynflow::ExecutionPlan', state: 'stopped' },
         { id: 'plan3', :label => 'test3', root_plan_step_id: 1, class: 'Dynflow::ExecutionPlan', state: 'paused' },
         { id: 'plan4', :label => 'test4', root_plan_step_id: 1, class: 'Dynflow::ExecutionPlan', state: 'paused' }]
      end

      let :action_data do
        {
         id: 1,
         caller_execution_plan_id: nil,
         caller_action_id: nil,
         class: 'Dynflow::Action',
         input: {key: 'value'},
         output: {something: 'else'},
         plan_step_id: 1,
         run_step_id: 2,
         finalize_step_id: 3
        }
      end

      let :step_data do
        { id: 1,
          state: 'success',
          started_at: Time.now.utc - 60,
          ended_at: Time.now.utc - 30,
          real_time: 1.1,
          execution_time: 0.1,
          action_id: 1,
          progress_done: 1,
          progress_weight: 2.5 }
      end

      def prepare_plans
        execution_plans_data.map do |h|
          h.merge result:    nil, started_at: Time.now.utc - 20, ended_at: Time.now.utc - 10,
              real_time: 0.0, execution_time: 0.0
        end
      end

      def prepare_and_save_plans
        prepare_plans.each { |plan| adapter.save_execution_plan(plan[:id], plan) }
      end

      def format_time(time)
        time.strftime('%Y-%m-%d %H:%M:%S')
      end

      def prepare_action(plan)
        adapter.save_action(plan, action_data[:id], action_data)
      end

      def prepare_step(plan)
        step = step_data.dup
        step[:execution_plan_uuid] = plan
        step
      end

      def prepare_and_save_step(plan)
        step = prepare_step(plan)
        adapter.save_step(plan, step[:id], step)
      end

      def prepare_plans_with_actions
        prepare_and_save_plans.each do |plan|
          prepare_action(plan[:id])
        end
      end

      def prepare_plans_with_steps
        prepare_plans_with_actions.map do |plan|
          prepare_and_save_step(plan[:id])
        end
      end

      def assert_equal_attributes!(original, loaded)
        original.each do |key, value|
          loaded_value = loaded[key.to_s]
          if value.is_a?(Time)
            loaded_value.inspect.must_equal value.inspect
          elsif value.is_a?(Hash)
            assert_equal_attributes!(value, loaded_value)
          else
            loaded[key.to_s].must_equal value
          end
        end
      end

      # rubocop:disable Metrics/AbcSize,Metrics/MethodLength
      def self.it_acts_as_persistence_adapter
        before do
          # the tests expect clean field
          adapter.delete_execution_plans({})
        end
        describe '#find_execution_plans' do
          it 'supports pagination' do
            prepare_and_save_plans
            if adapter.pagination?
              loaded_plans = adapter.find_execution_plans(page: 0, per_page: 1)
              loaded_plans.map { |h| h[:id] }.must_equal ['plan1']

              loaded_plans = adapter.find_execution_plans(page: 1, per_page: 1)
              loaded_plans.map { |h| h[:id] }.must_equal ['plan2']
            end
          end

          it 'supports ordering' do
            prepare_and_save_plans
            if adapter.ordering_by.include?('state')
              loaded_plans = adapter.find_execution_plans(order_by: 'state')
              loaded_plans.map { |h| h[:id] }.must_equal %w(plan1 plan3 plan4 plan2)

              loaded_plans = adapter.find_execution_plans(order_by: 'state', desc: true)
              loaded_plans.map { |h| h[:id] }.must_equal %w(plan2 plan1 plan3 plan4)
            end
          end

          it 'supports filtering' do
            prepare_and_save_plans
            if adapter.ordering_by.include?('state')
              loaded_plans = adapter.find_execution_plans(filters: { label: ['test1'] })
              loaded_plans.map { |h| h[:id] }.must_equal ['plan1']
              loaded_plans = adapter.find_execution_plans(filters: { state: ['paused'] })
              loaded_plans.map { |h| h[:id] }.must_equal ['plan1', 'plan3', 'plan4']

              loaded_plans = adapter.find_execution_plans(filters: { state: ['stopped'] })
              loaded_plans.map { |h| h[:id] }.must_equal ['plan2']

              loaded_plans = adapter.find_execution_plans(filters: { state: [] })
              loaded_plans.map { |h| h[:id] }.must_equal []

              loaded_plans = adapter.find_execution_plans(filters: { state: ['stopped', 'paused'] })
              loaded_plans.map { |h| h[:id] }.must_equal %w(plan1 plan2 plan3 plan4)

              loaded_plans = adapter.find_execution_plans(filters: { 'state' => ['stopped', 'paused'] })
              loaded_plans.map { |h| h[:id] }.must_equal %w(plan1 plan2 plan3 plan4)

              loaded_plans = adapter.find_execution_plans(filters: { label: ['test1'], :delayed => true })
              loaded_plans.must_be_empty

              adapter.save_delayed_plan('plan1',
                                        :execution_plan_uuid => 'plan1',
                                        :start_at => format_time(Time.now + 60),
                                        :start_before => format_time(Time.now - 60))
              loaded_plans = adapter.find_execution_plans(filters: { label: ['test1'], :delayed => true })
              loaded_plans.map { |h| h[:id] }.must_equal ['plan1']
            end
          end
        end

        describe '#def find_execution_plan_counts' do
          before do
            # the tests expect clean field
            adapter.delete_execution_plans({})
          end

          it 'supports filtering' do
            prepare_and_save_plans
            if adapter.ordering_by.include?('state')
              loaded_plans = adapter.find_execution_plan_counts(filters: { label: ['test1'] })
              loaded_plans.must_equal 1
              loaded_plans = adapter.find_execution_plan_counts(filters: { state: ['paused'] })
              loaded_plans.must_equal 3

              loaded_plans = adapter.find_execution_plan_counts(filters: { state: ['stopped'] })
              loaded_plans.must_equal 1

              loaded_plans = adapter.find_execution_plan_counts(filters: { state: [] })
              loaded_plans.must_equal 0

              loaded_plans = adapter.find_execution_plan_counts(filters: { state: ['stopped', 'paused'] })
              loaded_plans.must_equal 4

              loaded_plans = adapter.find_execution_plan_counts(filters: { 'state' => ['stopped', 'paused'] })
              loaded_plans.must_equal 4

              loaded_plans = adapter.find_execution_plan_counts(filters: { label: ['test1'], :delayed => true })
              loaded_plans.must_equal 0

              adapter.save_delayed_plan('plan1',
                                        :execution_plan_uuid => 'plan1',
                                        :start_at => format_time(Time.now + 60),
                                        :start_before => format_time(Time.now - 60))
              loaded_plans = adapter.find_execution_plan_counts(filters: { label: ['test1'], :delayed => true })
              loaded_plans.must_equal 1
            end
          end
        end

        describe '#load_execution_plan and #save_execution_plan' do
          it 'serializes/deserializes the plan data' do
            -> { adapter.load_execution_plan('plan1') }.must_raise KeyError
            plan = prepare_and_save_plans.first
            loaded_plan = adapter.load_execution_plan('plan1')
            loaded_plan[:id].must_equal 'plan1'
            loaded_plan['id'].must_equal 'plan1'

            assert_equal_attributes!(plan, loaded_plan)

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

          it 'creates backup dir and produce backup including steps and actions' do
            prepare_plans_with_steps
            Dir.mktmpdir do |backup_dir|
              adapter.delete_execution_plans({'uuid' => 'plan1'}, 100, backup_dir).must_equal 1
              plans = CSV.read(backup_dir + "/execution_plans.csv", :headers => true)
              assert_equal 1, plans.count
              assert_equal 'plan1', plans.first.to_hash['uuid']
              actions = CSV.read(backup_dir + "/actions.csv", :headers => true)
              assert_equal 1, actions.count
              assert_equal 'plan1', actions.first.to_hash['execution_plan_uuid']
              steps = CSV.read(backup_dir +"/steps.csv", :headers => true)
              assert_equal 1, steps.count
              assert_equal 'plan1', steps.first.to_hash['execution_plan_uuid']
            end
          end
        end

        describe '#load_action and #save_action' do
          it 'serializes/deserializes the action data' do
            prepare_and_save_plans
            action = action_data.dup
            action_id = action_data[:id]
            -> { adapter.load_action('plan1', action_id) }.must_raise KeyError

            prepare_action('plan1')
            loaded_action = adapter.load_action('plan1', action_id)
            loaded_action[:id].must_equal action_id

            assert_equal_attributes!(action, loaded_action)

            adapter.save_action('plan1', action_id, nil)
            -> { adapter.load_action('plan1', action_id) }.must_raise KeyError

            adapter.save_execution_plan('plan1', nil)
          end

          it 'allow to retrieve specific attributes using #load_actions_attributes' do
            prepare_and_save_plans
            prepare_action('plan1')
            loaded_data = adapter.load_actions_attributes('plan1', [:id, :run_step_id]).first
            loaded_data.keys.count.must_equal 2
            loaded_data[:id].must_equal action_data[:id]
            loaded_data[:run_step_id].must_equal action_data[:run_step_id]
          end

          it 'allows to load actions in bulk using #load_actions' do
            prepare_and_save_plans
            prepare_action('plan1')
            action = action_data.dup
            loaded_actions = adapter.load_actions('plan1', [1])
            loaded_actions.count.must_equal 1
            loaded_action = loaded_actions.first

            assert_equal_attributes!(action, loaded_action)
          end
        end

        describe '#load_step and #save_step' do
          it 'serializes/deserializes the step data' do
            prepare_plans_with_actions
            step_id = step_data[:id]
            prepare_and_save_step('plan1')
            loaded_step = adapter.load_step('plan1', step_id)
            loaded_step[:id].must_equal step_id

            assert_equal_attributes!(step_data, loaded_step)
          end
        end

        describe '#find_past_delayed_plans' do
          it 'finds plans with start_before in past' do
            start_time = Time.now.utc
            prepare_and_save_plans
            adapter.save_delayed_plan('plan1', :execution_plan_uuid => 'plan1', :frozen => false, :start_at => format_time(start_time + 60),
                                      :start_before => format_time(start_time - 60))
            adapter.save_delayed_plan('plan2', :execution_plan_uuid => 'plan2', :frozen => false, :start_at => format_time(start_time - 60))
            adapter.save_delayed_plan('plan3', :execution_plan_uuid => 'plan3', :frozen => false, :start_at => format_time(start_time + 60))
            adapter.save_delayed_plan('plan4', :execution_plan_uuid => 'plan4', :frozen => false, :start_at => format_time(start_time - 60),
                                      :start_before => format_time(start_time - 60))
            plans = adapter.find_past_delayed_plans(start_time)
            plans.length.must_equal 3
            plans.map { |plan| plan[:execution_plan_uuid] }.must_equal %w(plan2 plan4 plan1)
          end

          it 'does not find plans that are frozen' do
            start_time = Time.now.utc
            prepare_and_save_plans

            adapter.save_delayed_plan('plan1', :execution_plan_uuid => 'plan1', :frozen => false, :start_at => format_time(start_time + 60),
                                      :start_before => format_time(start_time - 60))
            adapter.save_delayed_plan('plan2', :execution_plan_uuid => 'plan2', :frozen => true, :start_at => format_time(start_time + 60),
                                      :start_before => format_time(start_time - 60))

            plans = adapter.find_past_delayed_plans(start_time)
            plans.length.must_equal 1
            plans.first[:execution_plan_uuid].must_equal 'plan1'
          end
        end
      end

      describe Dynflow::PersistenceAdapters::Sequel do
        let(:adapter) { Dynflow::PersistenceAdapters::Sequel.new 'sqlite:/' }

        it_acts_as_persistence_adapter

        it 'allows inspecting the persisted content' do
          plans = prepare_and_save_plans

          plans.each do |original|
            stored = adapter.to_hash.fetch(:execution_plans).find { |ep| ep[:uuid].strip == original[:id] }
            adapter.class::META_DATA.fetch(:execution_plan).each do |name|
              value = original.fetch(name.to_sym)
              if value.nil?
                stored.fetch(name.to_sym).must_be_nil
              elsif value.is_a?(Time)
                stored.fetch(name.to_sym).inspect.must_equal value.inspect
              else
                stored.fetch(name.to_sym).must_equal value
              end
            end
          end
        end

        it "supports connector's needs for exchaning envelopes" do
          client_world_id   = '5678'
          executor_world_id = '1234'
          envelope_hash = ->(envelope) { Dynflow::Utils.indifferent_hash(Dynflow.serializer.dump(envelope)) }
          executor_envelope = envelope_hash.call(Dispatcher::Envelope['123', client_world_id, executor_world_id, Dispatcher::Execution['111']])
          client_envelope   = envelope_hash.call(Dispatcher::Envelope['123', executor_world_id, client_world_id, Dispatcher::Accepted])
          envelopes         = [client_envelope, executor_envelope]

          envelopes.each { |e| adapter.push_envelope(e) }

          assert_equal [executor_envelope], adapter.pull_envelopes(executor_world_id)
          assert_equal [client_envelope],   adapter.pull_envelopes(client_world_id)
          assert_equal [], adapter.pull_envelopes(client_world_id)
          assert_equal [], adapter.pull_envelopes(executor_world_id)
        end

        it 'supports reading data saved prior to normalization' do
          db = adapter.send(:db)
          # Prepare records for saving
          plan = prepare_plans.first
          step_data = prepare_step(plan[:id])

          # We used to store times as strings
          plan[:started_at] = format_time plan[:started_at]
          plan[:ended_at] = format_time plan[:ended_at]
          step_data[:started_at] = format_time step_data[:started_at]
          step_data[:ended_at] = format_time step_data[:ended_at]

          plan_record = adapter.send(:prepare_record, :execution_plan, plan.merge(:uuid => plan[:id]))
          action_record = adapter.send(:prepare_record, :action, action_data.dup)
          step_record = adapter.send(:prepare_record, :step, step_data)

          # Insert the records
          db[:dynflow_execution_plans].insert plan_record.merge(:uuid => plan[:id])
          db[:dynflow_actions].insert action_record.merge(:execution_plan_uuid => plan[:id], :id => action_data[:id])
          db[:dynflow_steps].insert step_record.merge(:execution_plan_uuid => plan[:id], :id => step_data[:id])

          # Load the saved records
          loaded_plan   = adapter.load_execution_plan(plan[:id])
          loaded_action = adapter.load_action(plan[:id], action_data[:id])
          loaded_step   = adapter.load_step(plan[:id], step_data[:id])

          # Test
          assert_equal_attributes!(plan, loaded_plan)
          assert_equal_attributes!(action_data, loaded_action)
          assert_equal_attributes!(step_data, loaded_step)
        end

        it 'support updating data saved prior to normalization' do
          db = adapter.send(:db)
          plan = prepare_plans.first
          plan_data = plan.dup
          plan[:started_at] = format_time plan[:started_at]
          plan[:ended_at] = format_time plan[:ended_at]
          plan_record = adapter.send(:prepare_record, :execution_plan, plan.merge(:uuid => plan[:id]))

          # Save the plan the old way
          db[:dynflow_execution_plans].insert plan_record.merge(:uuid => plan[:id])

          # Update and save the plan
          plan_data[:state] = 'stopped'
          plan_data[:result] = 'success'
          adapter.save_execution_plan(plan[:id], plan_data)

          # Check the plan has the changed columns populated
          raw_plan = db[:dynflow_execution_plans].where(:uuid => 'plan1').first
          raw_plan[:state].must_equal 'stopped'
          raw_plan[:result].must_equal 'success'

          # Load the plan and assert it doesn't read attributes from data
          loaded_plan = adapter.load_execution_plan(plan[:id])
          assert_equal_attributes!(plan_data, loaded_plan)
        end
      end
    end
  end
end
