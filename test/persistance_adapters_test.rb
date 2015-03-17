require_relative 'test_helper'
require 'fileutils'

module Dynflow
  module PersistenceAdapterTest
    def persistence
      @persistence ||= Persistence.new(WorldFactory.create_world, adapter)
    end

    def adapter
      raise NotImplementedError
    end

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

    def test_load_execution_plans
      plans        = prepare_plans
      loaded_plans = adapter.find_execution_plans
      loaded_plans.size.must_equal 3
      loaded_plans.must_include plans[0].with_indifferent_access
      loaded_plans.must_include plans[1].with_indifferent_access
    end

    def test_pagination
      prepare_plans
      if adapter.pagination?
        loaded_plans = adapter.find_execution_plans(page: 0, per_page: 1)
        loaded_plans.map { |h| h[:id] }.must_equal ['plan1']

        loaded_plans = adapter.find_execution_plans(page: 1, per_page: 1)
        loaded_plans.map { |h| h[:id] }.must_equal ['plan2']
      end
    end

    def test_ordering
      prepare_plans
      if adapter.ordering_by.include?(:state)
        loaded_plans = adapter.find_execution_plans(order_by: 'state')
        loaded_plans.map { |h| h[:id] }.must_equal ['plan1', 'plan3', 'plan2']

        loaded_plans = adapter.find_execution_plans(order_by: 'state', desc: true)
        loaded_plans.map { |h| h[:id] }.must_equal ['plan2', 'plan3', 'plan1']
      end
    end

    def test_filtering
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

    def test_execution_plan
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

    def test_action
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

    def test_envelopes
      client_world_id   = '5678'
      executor_world_id = '1234'
      executor_envelope = Dispatcher::Envelope[123, client_world_id, executor_world_id, Dispatcher::Execution['111']]
      client_envelope   = Dispatcher::Envelope[123, executor_world_id, client_world_id, Dispatcher::Accepted]
      envelopes         = [client_envelope, executor_envelope]

      envelopes.each { |e| persistence.push_envelope(e) }

      assert_equal [executor_envelope], persistence.pull_envelopes(executor_world_id)
      assert_equal [client_envelope],   persistence.pull_envelopes(client_world_id)
      assert_equal [], persistence.pull_envelopes(client_world_id)
      assert_equal [], persistence.pull_envelopes(executor_world_id)

      envelopes.each { |e| persistence.push_envelope(e) }
    end
  end

  class SequelTest < MiniTest::Spec
    include PersistenceAdapterTest

    def adapter
      @adapter ||= Dynflow::PersistenceAdapters::Sequel.new 'sqlite:/'
    end

    def test_stores_meta_data
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
