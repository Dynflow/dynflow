require_relative 'test_helper'
require 'fileutils'

module PersistenceAdapterTest
  def storage
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
      plans.each { |plan| storage.save_execution_plan(plan[:id], plan) }
    end
  end

  def test_load_execution_plans
    plans        = prepare_plans
    loaded_plans = storage.find_execution_plans
    loaded_plans.size.must_equal 3
    loaded_plans.must_include plans[0].with_indifferent_access
    loaded_plans.must_include plans[1].with_indifferent_access
  end

  def test_pagination
    prepare_plans
    if storage.pagination?
      loaded_plans = storage.find_execution_plans(page: 0, per_page: 1)
      loaded_plans.map { |h| h[:id] }.must_equal ['plan1']

      loaded_plans = storage.find_execution_plans(page: 1, per_page: 1)
      loaded_plans.map { |h| h[:id] }.must_equal ['plan2']
    end
  end

  def test_ordering
    prepare_plans
    if storage.ordering_by.include?(:state)
      loaded_plans = storage.find_execution_plans(order_by: 'state')
      loaded_plans.map { |h| h[:id] }.must_equal ['plan1', 'plan3', 'plan2']

      loaded_plans = storage.find_execution_plans(order_by: 'state', desc: true)
      loaded_plans.map { |h| h[:id] }.must_equal ['plan2', 'plan3', 'plan1']
    end
  end

  def test_filtering
    prepare_plans
    if storage.ordering_by.include?(:state)
      loaded_plans = storage.find_execution_plans(filters: { state: ['paused'] })
      loaded_plans.map { |h| h[:id] }.must_equal ['plan1', 'plan3']

      loaded_plans = storage.find_execution_plans(filters: { state: ['stopped'] })
      loaded_plans.map { |h| h[:id] }.must_equal ['plan2']

      loaded_plans = storage.find_execution_plans(filters: { state: [] })
      loaded_plans.map { |h| h[:id] }.must_equal []

      loaded_plans = storage.find_execution_plans(filters: { state: ['stopped', 'paused'] })
      loaded_plans.map { |h| h[:id] }.must_equal ['plan1', 'plan2', 'plan3']

      loaded_plans = storage.find_execution_plans(filters: { 'state' => ['stopped', 'paused'] })
      loaded_plans.map { |h| h[:id] }.must_equal ['plan1', 'plan2', 'plan3']
    end
  end

  def test_save_execution_plan
    plan = { id:        'plan1', state: :pending, result: nil, started_at: nil, ended_at: nil,
             real_time: 0.0, execution_time: 0.0 }
    -> { storage.load_execution_plan('plan1') }.must_raise KeyError

    storage.save_execution_plan('plan1', plan)
    storage.load_execution_plan('plan1')[:id].must_equal 'plan1'
    storage.load_execution_plan('plan1')['id'].must_equal 'plan1'
    storage.load_execution_plan('plan1').keys.size.must_equal 7

    storage.save_execution_plan('plan1', nil)
    -> { storage.load_execution_plan('plan1') }.must_raise KeyError
  end

  def test_save_action
    plan = { id:        'plan1', state: :pending, result: nil, started_at: nil, ended_at: nil,
             real_time: 0.0, execution_time: 0.0 }
    storage.save_execution_plan('plan1', plan)

    action = { id: 1 }
    -> { storage.load_action('plan1', 1) }.must_raise KeyError

    storage.save_action('plan1', 1, action)
    storage.load_action('plan1', 1)[:id].must_equal 1
    storage.load_action('plan1', 1)['id'].must_equal 1
    storage.load_action('plan1', 1).keys.size.must_equal 1

    storage.save_action('plan1', 1, nil)
    -> { storage.load_action('plan1', 1) }.must_raise KeyError

    storage.save_execution_plan('plan1', nil)
  end

end

class SequelTest < MiniTest::Spec
  include PersistenceAdapterTest

  def storage
    @storage ||= Dynflow::PersistenceAdapters::Sequel.new 'sqlite:/'
  end

  def test_stores_meta_data
    plans = prepare_plans

    plans.each do |original|
      stored = storage.to_hash.fetch(:execution_plans).find { |ep| ep[:uuid] == original[:id] }
      stored.each { |k, v| stored[k] = v.to_s if v.is_a? Time }
      storage.class::META_DATA.fetch(:execution_plan).each do |name|
        stored.fetch(name.to_sym).must_equal original.fetch(name.to_sym)
      end
    end
  end
end

#class MemoryTest < MiniTest::Unit::TestCase
#  include PersistenceAdapterTest
#
#  def storage
#    @storage ||= Dynflow::PersistenceAdapters::Memory.new
#  end
#end
#
#class SimpleFileStorageTest < MiniTest::Unit::TestCase
#  include PersistenceAdapterTest
#
#  def storage_path
#    "#{File.dirname(__FILE__)}/simple_file_storage"
#  end
#
#  def setup
#    Dir.mkdir storage_path
#  end
#
#  def storage
#    @storage ||= begin
#      Dynflow::PersistenceAdapters::SimpleFileStorage.new storage_path
#    end
#  end
#
#  def teardown
#    FileUtils.rm_rf storage_path
#  end
#end
#
#require 'dynflow/persistence_adapters/active_record'
#
#class ActiveRecordTest < MiniTest::Unit::TestCase
#  include PersistenceAdapterTest
#
#  def setup
#    ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: ':memory:')
#    ::ActiveRecord::Migrator.migrate Dynflow::PersistenceAdapters::ActiveRecord.migrations_path
#  end
#
#  def storage
#    @storage ||= begin
#      Dynflow::PersistenceAdapters::ActiveRecord.new
#    end
#  end
#end


