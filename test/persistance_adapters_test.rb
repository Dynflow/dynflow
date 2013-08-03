require_relative 'test_helper'
require 'fileutils'

module PersistenceAdapterTest
  def storage
    raise NotImplementedError
  end

  def test_load_execution_plans
    plans = [{ id: 'plan1' }, { id: 'plan2' }]
    plans.each { |plan| storage.save_execution_plan(plan[:id], plan) }
    loaded_plans = storage.find_execution_plans
    loaded_plans.size.must_equal 2
    loaded_plans.must_include plans[0].with_indifferent_access
    loaded_plans.must_include plans[1].with_indifferent_access
  end

  def test_save_execution_plan
    plan = { id: 'plan1' }
    -> { storage.load_execution_plan('plan1') }.must_raise KeyError

    storage.save_execution_plan('plan1', plan)
    storage.load_execution_plan('plan1')[:id].must_equal 'plan1'
    storage.load_execution_plan('plan1')['id'].must_equal 'plan1'
    storage.load_execution_plan('plan1').keys.size.must_equal 1

    storage.save_execution_plan('plan1', nil)
    -> { storage.load_execution_plan('plan1') }.must_raise KeyError
  end

  def test_save_action
    action = { id: 1 }
    -> { storage.load_action('plan1', 1) }.must_raise KeyError

    storage.save_action('plan1', 1, action)
    storage.load_action('plan1', 1)[:id].must_equal 1
    storage.load_action('plan1', 1)['id'].must_equal 1
    storage.load_action('plan1', 1).keys.size.must_equal 1

    storage.save_action('plan1', 1, nil)
    -> { storage.load_action('plan1', 1) }.must_raise KeyError
  end
end

class MemoryTest < MiniTest::Unit::TestCase
  include PersistenceAdapterTest

  def storage
    @storage ||= Dynflow::PersistenceAdapters::Memory.new
  end
end

class SimpleFileStorageTest < MiniTest::Unit::TestCase
  include PersistenceAdapterTest

  def storage_path
    "#{File.dirname(__FILE__)}/simple_file_storage"
  end

  def setup
    Dir.mkdir storage_path
  end

  def storage
    @storage ||= begin
      Dynflow::PersistenceAdapters::SimpleFileStorage.new storage_path
    end
  end

  def teardown
    FileUtils.rm_rf storage_path
  end
end

require 'dynflow/persistence_adapters/active_record'

class ActiveRecordTest < MiniTest::Unit::TestCase
  include PersistenceAdapterTest

  def setup
    ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: ':memory:')
    ::ActiveRecord::Migrator.migrate Dynflow::PersistenceAdapters::ActiveRecord.migrations_path
  end

  def storage
    @storage ||= begin
      Dynflow::PersistenceAdapters::ActiveRecord.new
    end
  end
end


