require_relative 'test_helper'
require 'fileutils'

module Dynflow
  module PersistenceTest
    describe 'persistence adapters' do
      def prepare_plans
        proto_plans = [{ id: 'plan1', state: 'paused' },
                       { id: 'plan2', state: 'stopped' },
                       { id: 'plan3', state: 'paused' }]
        proto_plans.map do |h|
          h.merge result:    nil, started_at: (Time.now-20).to_s, ended_at: (Time.now-10).to_s,
              real_time: 0.0, execution_time: 0.0
        end.tap do |plans|
          plans.each { |plan| adapter.save_execution_plan(plan[:id], plan) }
        end
      end

      def self.it_acts_as_persistence_adapter
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
          it 'serializes/deserializes the plan data from the storage' do
            plan = { id:        'plan1', state: :pending, result: nil, started_at: nil, ended_at: nil,
                     real_time: 0.0, execution_time: 0.0 }
            -> { adapter.load_execution_plan('plan1') }.must_raise KeyError

            adapter.save_execution_plan('plan1', plan)
            adapter.load_execution_plan('plan1')[:id].must_equal 'plan1'
            adapter.load_execution_plan('plan1')['id'].must_equal 'plan1'
            adapter.load_execution_plan('plan1').keys.size.must_equal 7

            adapter.save_execution_plan('plan1', nil)
            -> { adapter.load_execution_plan('plan1') }.must_raise KeyError
          end
        end

        describe '#load_action and #save_action' do
          it 'serializes/deserializes the action data from the storage' do
            plan = { id:        'plan1', state: :pending, result: nil, started_at: nil, ended_at: nil,
                     real_time: 0.0, execution_time: 0.0 }
            adapter.save_execution_plan('plan1', plan)

            action = { id: 1, caller_execution_plan_id: nil, caller_action_id: nil }
            -> { adapter.load_action('plan1', 1) }.must_raise KeyError

            adapter.save_action('plan1', 1, action)
            adapter.load_action('plan1', 1)[:id].must_equal 1
            adapter.load_action('plan1', 1)['id'].must_equal 1
            adapter.load_action('plan1', 1).keys.must_equal %w[id caller_execution_plan_id caller_action_id]

            adapter.save_action('plan1', 1, nil)
            -> { adapter.load_action('plan1', 1) }.must_raise KeyError

            adapter.save_execution_plan('plan1', nil)
          end
        end
      end

      describe Dynflow::PersistenceAdapters::Sequel do
        let(:adapter) { Dynflow::PersistenceAdapters::Sequel.new 'sqlite:/' }

        it_acts_as_persistence_adapter

        it 'allows inspecting the persisted content' do
          plans = prepare_plans

          plans.each do |original|
            stored = adapter.to_hash.fetch(:execution_plans).find { |ep| ep[:uuid] == original[:id] }
            stored.each { |k, v| stored[k] = v.to_s if v.is_a? Time }
            adapter.class::META_DATA.fetch(:execution_plan).each do |name|
              stored.fetch(name.to_sym).must_equal original.fetch(name.to_sym)
            end
          end
        end
      end
    end
  end
end
